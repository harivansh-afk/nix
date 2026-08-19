// Prints the largest NSScreen.safeAreaInsets.top (the notch strip height, in
// points) across all screens, or 0 when no screen has one.
#import <AppKit/AppKit.h>
int main(void) {
  @autoreleasepool {
    CGFloat top = 0;
    for (NSScreen *s in [NSScreen screens]) {
      if (@available(macOS 12.0, *)) {
        CGFloat t = s.safeAreaInsets.top;
        if (t > top) top = t;
      }
    }
    printf("%d\n", (int)top);
  }
  return 0;
}
