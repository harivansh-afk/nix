// sketchybar-feed: one long-lived process that pushes every dynamic value in
// the bar (workspace tabs, cpu/mem, volume, battery, clock, display watchdog)
// straight into sketchybar over its mach port. It replaces the per-item
// `script=` / `update_freq=` plugins: nothing here forks a shell, and the
// only child processes are `aerospace list-*` on a workspace/app event.
//
// Sources, all push-based system APIs:
//   volume    CoreAudio property listeners on the default output device
//   battery   IOKit power-source notification
//   displays  CoreGraphics reconfiguration callback (reloads the rc, which
//             re-measures the notch height, when the display set changes)
//   spaces    aerospace's exec-on-workspace-change hook (SIGUSR2) plus
//             NSWorkspace app activate/launch/terminate notifications
//   clock     one timer aligned to the minute
//   cpu/mem   host_processor_info deltas and kern.memorystatus_level, 5s
//
// Signals: SIGUSR1 = the rc finished (re)loading, re-read the theme and push
// everything; SIGUSR2 = aerospace workspace change.
//
// CLI mode (`sketchybar-feed volume-event`) is the volume item's mouse
// script: it sets the device volume/mute via CoreAudio and exits; the daemon's
// listener renders the result.

#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioServices.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPSKeys.h>
#import <IOKit/ps/IOPowerSources.h>
#import <bootstrap.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/processor_info.h>
#import <signal.h>
#import <sys/sysctl.h>

#include "icon_map.h"

// ---------------------------------------------------------------- mach ---

// Wire format is sketchybar's own CLI encoding: argv joined by NUL, double NUL
// at the end, sent as an out-of-line descriptor to "git.felix.sketchybar".
struct mach_message {
  mach_msg_header_t header;
  mach_msg_size_t msgh_descriptor_count;
  mach_msg_ool_descriptor_t descriptor;
};

struct mach_buffer {
  struct mach_message message;
  mach_msg_trailer_t trailer;
};

static mach_port_t g_sb_port = MACH_PORT_NULL;

static mach_port_t sb_lookup(void) {
  mach_port_t bs_port;
  if (task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &bs_port) != KERN_SUCCESS) return MACH_PORT_NULL;
  mach_port_t port = MACH_PORT_NULL;
  if (bootstrap_look_up(bs_port, "git.felix.sketchybar", &port) != KERN_SUCCESS) return MACH_PORT_NULL;
  return port;
}

// Returns sketchybar's response (may be empty), or nil when the daemon is
// not reachable. Always awaits the reply so the daemon paces us.
static NSString *sb_send(NSArray<NSString *> *argv) {
  if (g_sb_port == MACH_PORT_NULL) g_sb_port = sb_lookup();
  if (g_sb_port == MACH_PORT_NULL) return nil;

  NSMutableData *buf = [NSMutableData data];
  for (NSString *a in argv) {
    [buf appendData:[a dataUsingEncoding:NSUTF8StringEncoding]];
    [buf appendBytes:"" length:1];
  }
  [buf appendBytes:"" length:1];

  mach_port_t reply;
  if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &reply) != KERN_SUCCESS) return nil;
  mach_port_insert_right(mach_task_self(), reply, reply, MACH_MSG_TYPE_MAKE_SEND);

  struct mach_message msg = {0};
  msg.header.msgh_remote_port = g_sb_port;
  msg.header.msgh_local_port = reply;
  msg.header.msgh_id = reply;
  msg.header.msgh_bits = MACH_MSGH_BITS_SET(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND, 0, MACH_MSGH_BITS_COMPLEX);
  msg.header.msgh_size = sizeof(msg);
  msg.msgh_descriptor_count = 1;
  msg.descriptor.address = (void *)buf.bytes;
  msg.descriptor.size = (mach_msg_size_t)buf.length;
  msg.descriptor.copy = MACH_MSG_VIRTUAL_COPY;
  msg.descriptor.deallocate = false;
  msg.descriptor.type = MACH_MSG_OOL_DESCRIPTOR;

  NSString *rsp = nil;
  kern_return_t kr = mach_msg(&msg.header, MACH_SEND_MSG, sizeof(msg), 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
  if (kr == MACH_MSG_SUCCESS) {
    struct mach_buffer in = {0};
    kr = mach_msg(&in.message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof(in), reply, 2000, MACH_PORT_NULL);
    if (kr == MACH_MSG_SUCCESS && in.message.descriptor.address) {
      rsp = [NSString stringWithUTF8String:in.message.descriptor.address] ?: @"";
      mach_msg_destroy(&in.message.header);
    } else {
      rsp = @"";
    }
  } else {
    // Send right went stale (sketchybar restarted): drop it, re-lookup next time.
    mach_port_deallocate(mach_task_self(), g_sb_port);
    g_sb_port = MACH_PORT_NULL;
  }
  mach_port_mod_refs(mach_task_self(), reply, MACH_PORT_RIGHT_RECEIVE, -1);
  mach_port_deallocate(mach_task_self(), reply);
  return rsp;
}

static void sb(NSArray<NSString *> *argv) { (void)sb_send(argv); }

// --------------------------------------------------------------- theme ---

static NSMutableDictionary<NSString *, NSString *> *g_theme;

static void theme_load(void) {
  g_theme = [NSMutableDictionary dictionary];
  NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/sketchybar/themes/current"];
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
    NSString *l = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([l hasPrefix:@"export "]) l = [l substringFromIndex:7];
    NSRange eq = [l rangeOfString:@"="];
    if (eq.location == NSNotFound) continue;
    g_theme[[l substringToIndex:eq.location]] = [l substringFromIndex:eq.location + 1];
  }
}

static NSString *color(NSString *key) { return g_theme[key] ?: @"0xffffffff"; }

// --------------------------------------------------------------- clock ---

static void clock_push(void) {
  time_t now = time(NULL);
  struct tm tm;
  localtime_r(&now, &tm);
  char date[32], clk[32];
  strftime(date, sizeof date, "%a %d %b", &tm);
  strftime(clk, sizeof clk, "%l:%M %p", &tm);
  const char *t = clk[0] == ' ' ? clk + 1 : clk;
  sb(@[ @"--set", @"clock", [NSString stringWithFormat:@"icon=%s", date], [NSString stringWithFormat:@"label=%s", t] ]);
}

static void clock_start(void) {
  time_t now = time(NULL);
  CFAbsoluteTime next = CFAbsoluteTimeGetCurrent() + (60 - now % 60) + 0.2;
  CFRunLoopTimerRef t = CFRunLoopTimerCreateWithHandler(NULL, next, 60, 0, 0, ^(CFRunLoopTimerRef _) { clock_push(); });
  CFRunLoopAddTimer(CFRunLoopGetMain(), t, kCFRunLoopCommonModes);
  clock_push();
}

// ------------------------------------------------------------- battery ---

static void battery_push(void) {
  CFTypeRef info = IOPSCopyPowerSourcesInfo();
  if (!info) return;
  CFArrayRef list = IOPSCopyPowerSourcesList(info);
  for (CFIndex i = 0; list && i < CFArrayGetCount(list); i++) {
    NSDictionary *ps = (__bridge NSDictionary *)IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
    if (![ps[@(kIOPSTypeKey)] isEqual:@(kIOPSInternalBatteryType)]) continue;
    int pct = [ps[@(kIOPSCurrentCapacityKey)] intValue];
    BOOL ac = [ps[@(kIOPSPowerSourceStateKey)] isEqual:@(kIOPSACPowerValue)];
    NSString *col = (!ac && pct <= 15) ? color(@"RED_COLOR") : color(@"TEXT_COLOR");
    sb(@[
      @"--set", @"battery", ac ? @"icon=chg" : @"icon=bat", [NSString stringWithFormat:@"label=%d%%", pct],
      [NSString stringWithFormat:@"label.color=%@", col]
    ]);
    break;
  }
  if (list) CFRelease(list);
  CFRelease(info);
}

static void battery_changed(void *ctx) { battery_push(); }

static void battery_start(void) {
  CFRunLoopSourceRef src = IOPSNotificationCreateRunLoopSource(battery_changed, NULL);
  if (src) CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
  battery_push();
}

// -------------------------------------------------------------- volume ---

static AudioObjectID g_out_dev = kAudioObjectUnknown;

static AudioObjectPropertyAddress vol_addr = {kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
static AudioObjectPropertyAddress mute_addr = {kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
static AudioObjectPropertyAddress default_addr = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};

static AudioObjectID default_output(void) {
  AudioObjectID dev = kAudioObjectUnknown;
  UInt32 sz = sizeof dev;
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &default_addr, 0, NULL, &sz, &dev);
  return dev;
}

static int volume_percent(AudioObjectID dev) {
  Float32 v = 0;
  UInt32 sz = sizeof v;
  if (AudioObjectGetPropertyData(dev, &vol_addr, 0, NULL, &sz, &v) != noErr) return -1;
  return (int)lroundf(v * 100);
}

static BOOL volume_muted(AudioObjectID dev) {
  UInt32 m = 0, sz = sizeof m;
  if (AudioObjectGetPropertyData(dev, &mute_addr, 0, NULL, &sz, &m) != noErr) return NO;
  return m != 0;
}

static void volume_push(void) {
  AudioObjectID dev = g_out_dev != kAudioObjectUnknown ? g_out_dev : default_output();
  if (dev == kAudioObjectUnknown) return;
  int pct = volume_percent(dev);
  if (volume_muted(dev)) {
    sb(@[ @"--set", @"volume", @"label=mute", [NSString stringWithFormat:@"label.color=%@", color(@"MUTED_COLOR")] ]);
  } else if (pct >= 0) {
    sb(@[ @"--set", @"volume", [NSString stringWithFormat:@"label=%d%%", pct], [NSString stringWithFormat:@"label.color=%@", color(@"TEXT_COLOR")] ]);
  }
}

static void volume_attach(void);

static AudioObjectPropertyListenerBlock g_vol_block = ^(UInt32 n, const AudioObjectPropertyAddress *a) { dispatch_async(dispatch_get_main_queue(), ^{ volume_push(); }); };
static AudioObjectPropertyListenerBlock g_default_block = ^(UInt32 n, const AudioObjectPropertyAddress *a) { dispatch_async(dispatch_get_main_queue(), ^{ volume_attach(); }); };

static void volume_attach(void) {
  if (g_out_dev != kAudioObjectUnknown) {
    AudioObjectRemovePropertyListenerBlock(g_out_dev, &vol_addr, dispatch_get_main_queue(), g_vol_block);
    AudioObjectRemovePropertyListenerBlock(g_out_dev, &mute_addr, dispatch_get_main_queue(), g_vol_block);
  }
  g_out_dev = default_output();
  if (g_out_dev != kAudioObjectUnknown) {
    AudioObjectAddPropertyListenerBlock(g_out_dev, &vol_addr, dispatch_get_main_queue(), g_vol_block);
    AudioObjectAddPropertyListenerBlock(g_out_dev, &mute_addr, dispatch_get_main_queue(), g_vol_block);
  }
  volume_push();
}

static void volume_start(void) {
  AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &default_addr, dispatch_get_main_queue(), g_default_block);
  volume_attach();
}

// Mouse handler for the volume item, run as a short-lived CLI process by
// sketchybar (SENDER / SCROLL_DELTA in the environment, like any plugin).
static int volume_event(void) {
  AudioObjectID dev = default_output();
  if (dev == kAudioObjectUnknown) return 1;
  const char *sender = getenv("SENDER") ?: "";
  if (strcmp(sender, "mouse.clicked") == 0) {
    UInt32 m = volume_muted(dev) ? 0 : 1;
    AudioObjectSetPropertyData(dev, &mute_addr, 0, NULL, sizeof m, &m);
  } else if (strcmp(sender, "mouse.scrolled") == 0) {
    int delta = atoi(getenv("SCROLL_DELTA") ?: "0");
    int pct = volume_percent(dev);
    if (pct < 0) return 1;
    pct += delta;
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    Float32 v = pct / 100.0f;
    AudioObjectSetPropertyData(dev, &vol_addr, 0, NULL, sizeof v, &v);
  }
  return 0;
}

// --------------------------------------------------------------- stats ---

static uint64_t g_cpu_prev_busy, g_cpu_prev_total;

static void stats_push(void) {
  natural_t ncpu;
  processor_info_array_t info;
  mach_msg_type_number_t count;
  if (host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count) != KERN_SUCCESS) return;
  uint64_t busy = 0, total = 0;
  for (natural_t i = 0; i < ncpu; i++) {
    integer_t *t = info + i * CPU_STATE_MAX;
    busy += t[CPU_STATE_USER] + t[CPU_STATE_SYSTEM] + t[CPU_STATE_NICE];
    total += t[CPU_STATE_USER] + t[CPU_STATE_SYSTEM] + t[CPU_STATE_NICE] + t[CPU_STATE_IDLE];
  }
  vm_deallocate(mach_task_self(), (vm_address_t)info, count * sizeof(integer_t));
  uint64_t db = busy - g_cpu_prev_busy, dt = total - g_cpu_prev_total;
  BOOL first = g_cpu_prev_total == 0;
  g_cpu_prev_busy = busy;
  g_cpu_prev_total = total;
  if (first || dt == 0) return;
  int cpu = (int)lround(100.0 * db / dt);

  int level = 0;
  size_t sz = sizeof level;
  if (sysctlbyname("kern.memorystatus_level", &level, &sz, NULL, 0) != 0) return;
  int mem = 100 - level;
  sb(@[ @"--set", @"resources", [NSString stringWithFormat:@"icon=mem %d%%", mem], [NSString stringWithFormat:@"label=cpu %d%%", cpu] ]);
}

static void stats_start(void) {
  stats_push(); // primes the counters
  CFRunLoopTimerRef t = CFRunLoopTimerCreateWithHandler(NULL, CFAbsoluteTimeGetCurrent() + 1, 5, 0, 0, ^(CFRunLoopTimerRef _) { stats_push(); });
  CFRunLoopAddTimer(CFRunLoopGetMain(), t, kCFRunLoopCommonModes);
}

// ------------------------------------------------------------ displays ---

// The rc measures the notch height and per-display edge spacers at load
// time and sketchybar fires no event for a resolution change, so the display
// set is stamped at each load and the rc reloaded when it drifts.
static NSString *g_display_stamp;

static void displays_check(void) {
  NSString *now = sb_send(@[ @"--query", @"displays" ]);
  if (now.length == 0) return;
  if (g_display_stamp && ![now isEqualToString:g_display_stamp]) {
    g_display_stamp = now;
    sb(@[ @"--reload" ]);
  } else {
    g_display_stamp = now;
  }
}

// Called twice per change (begin, then end); act on the end callback only.
static void displays_changed(CGDirectDisplayID d, CGDisplayChangeSummaryFlags flags, void *ctx) {
  if (flags & kCGDisplayBeginConfigurationFlag) return;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ displays_check(); });
}

static void displays_start(void) {
  CGDisplayRegisterReconfigurationCallback(displays_changed, NULL);
  displays_check();
}

// -------------------------------------------------------------- spaces ---

static NSString *g_aerospace; // resolved once from PATH

static NSString *run(NSArray<NSString *> *argv) {
  NSTask *t = [NSTask new];
  t.executableURL = [NSURL fileURLWithPath:argv[0]];
  t.arguments = [argv subarrayWithRange:NSMakeRange(1, argv.count - 1)];
  NSPipe *p = [NSPipe pipe];
  t.standardOutput = p;
  t.standardError = [NSFileHandle fileHandleWithNullDevice];
  if (![t launchAndReturnError:nil]) return nil;
  NSData *d = [p.fileHandleForReading readDataToEndOfFile];
  [t waitUntilExit];
  return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

static NSString *icon_for(NSString *app) {
  const char *a = app.UTF8String;
  for (size_t i = 0; i < ICON_MAP_COUNT; i++) {
    const struct icon_map_entry *e = &icon_map[i];
    if (e->prefix ? strncmp(a, e->name, strlen(e->name)) == 0 : strcmp(a, e->name) == 0) return @(e->icon);
  }
  return @":default:";
}

static void spaces_push(void) {
  if (!g_aerospace) return;
  NSString *focused = [run(@[ g_aerospace, @"list-workspaces", @"--focused" ]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  NSString *windows = run(@[ g_aerospace, @"list-windows", @"--all", @"--format", @"%{workspace}|%{app-name}" ]);
  if (!focused || !windows) return;

  // first app per workspace, alphabetically (mirrors `sort -u | head -1`)
  NSMutableDictionary<NSString *, NSString *> *first = [NSMutableDictionary dictionary];
  for (NSString *line in [windows componentsSeparatedByString:@"\n"]) {
    NSRange bar = [line rangeOfString:@"|"];
    if (bar.location == NSNotFound) continue;
    NSString *ws = [line substringToIndex:bar.location];
    NSString *app = [line substringFromIndex:bar.location + 1];
    if (!first[ws] || [app compare:first[ws]] == NSOrderedAscending) first[ws] = app;
  }

  // tab internals mirror the rc: 10/11/10pt compensates font side bearings
  NSMutableArray *args = [NSMutableArray array];
  for (int sid = 1; sid <= 9; sid++) {
    NSString *id = [NSString stringWithFormat:@"%d", sid];
    NSString *item = [@"space." stringByAppendingString:id];
    NSString *app = first[id];
    NSString *icon = app ? icon_for(app) : @"";
    BOOL isFocused = [id isEqualToString:focused];
    if (!isFocused && icon.length == 0) {
      [args addObjectsFromArray:@[ @"--set", item, @"drawing=off" ]];
      continue;
    }
    NSString *fg = isFocused ? color(@"PINK_COLOR") : color(@"MUTED_COLOR");
    [args addObjectsFromArray:@[
      @"--set", item, @"drawing=on",
      [NSString stringWithFormat:@"background.color=%@", color(@"BAR_COLOR")],
      [NSString stringWithFormat:@"icon.color=%@", fg],
      isFocused ? @"icon.font=Berkeley Mono:Bold:18.0" : @"icon.font=Berkeley Mono:Regular:18.0",
      icon.length ? @"icon.padding_right=11" : @"icon.padding_right=10",
      [NSString stringWithFormat:@"label=%@", icon],
      icon.length ? @"label.drawing=on" : @"label.drawing=off",
      [NSString stringWithFormat:@"label.color=%@", isFocused ? color(@"TEXT_COLOR") : color(@"MUTED_COLOR")],
    ]];
  }
  sb(args);
}

static BOOL g_spaces_pending;
static void spaces_schedule(void) {
  if (g_spaces_pending) return;
  g_spaces_pending = YES;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 100), dispatch_get_main_queue(), ^{
    g_spaces_pending = NO;
    spaces_push();
  });
}

static void spaces_start(void) {
  for (NSString *dir in [(getenv("PATH") ? @(getenv("PATH")) : @"") componentsSeparatedByString:@":"]) {
    NSString *p = [dir stringByAppendingPathComponent:@"aerospace"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:p]) { g_aerospace = p; break; }
  }
  if (!g_aerospace) fprintf(stderr, "sketchybar-feed: aerospace not on PATH, workspace tabs disabled\n");
  NSNotificationCenter *nc = NSWorkspace.sharedWorkspace.notificationCenter;
  for (NSNotificationName n in @[ NSWorkspaceDidActivateApplicationNotification, NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification ]) {
    [nc addObserverForName:n object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *_) { spaces_schedule(); }];
  }
  spaces_push();
}

// ---------------------------------------------------------------- main ---

static void push_all(void) {
  theme_load();
  clock_push();
  battery_push();
  volume_push();
  stats_push();
  spaces_push();
}

static void on_signal(int sig, dispatch_block_t handler) {
  signal(sig, SIG_IGN);
  dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, sig, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(s, handler);
  dispatch_resume(s);
  // keep the source alive for the process lifetime
  static NSMutableArray *keep;
  if (!keep) keep = [NSMutableArray array];
  [keep addObject:s];
}

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc > 1 && strcmp(argv[1], "volume-event") == 0) return volume_event();

    // sketchybar and this agent start together at login; wait for its port.
    while ((g_sb_port = sb_lookup()) == MACH_PORT_NULL) usleep(500 * 1000);

    theme_load();
    on_signal(SIGUSR1, ^{ push_all(); });
    on_signal(SIGUSR2, ^{ spaces_schedule(); });
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *_) { push_all(); }];

    clock_start();
    battery_start();
    volume_start();
    stats_start();
    displays_start();
    spaces_start();

    [[NSRunLoop mainRunLoop] run];
  }
  return 0;
}
