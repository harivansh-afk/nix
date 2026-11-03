{
  config,
  lib,
  pkgs,
  ...
}:
{
  security.lsm = lib.mkForce [
    "landlock"
    "yama"
    "apparmor"
    "bpf"
  ];

  boot = {
    kexec.enable = false;
    kernelModules = [
      "br_netfilter"
      "ib_umad"
      "nvme_fabrics"
      "nvme_tcp"
      "overlay"
      "rdma_cm"
      "veth"
      "xt_addrtype"
      "xt_comment"
      "xt_multiport"
      "xt_nat"
    ];
    kernelParams = [
      "hardened_usercopy=1"
      "hash_pointers=always"
      "init_on_alloc=1"
      "iommu.passthrough=0"
      "iommu.strict=1"
      "mitigations=auto,nosmt"
      "page_alloc.shuffle=1"
      "panic=10"
      "sbsa_gwdt.action=1"
      "sbsa_gwdt.timeout=30"
      "proc_mem.force_override=never"
      "randomize_kstack_offset=on"
      "slab_nomerge"
    ];
    kernel.sysctl = {
      "dev.tty.ldisc_autoload" = 0;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      "fs.suid_dumpable" = 0;
      "kernel.apparmor_restrict_unprivileged_userns" = 0;
      "kernel.dmesg_restrict" = 1;
      "kernel.kptr_restrict" = 2;
      "kernel.unprivileged_bpf_disabled" = 1;
      "kernel.yama.ptrace_scope" = 2;
    };
    specialFileSystems."/proc".options = [ "hidepid=invisible" ];
  };

  security = {
    apparmor.enable = true;
    audit = {
      enable = true;
      backlogLimit = 8192;
      failureMode = "printk";
      rules = [
        "-a always,exit -F arch=b64 -S bpf -k bpf"
        "-a always,exit -F arch=b64 -S delete_module,finit_module,init_module -k modules"
        "-a always,exit -F arch=b64 -S kexec_file_load,kexec_load -k kexec"
        "-a always,exit -F arch=b64 -S adjtimex,clock_settime,settimeofday -k time"
        "-w /boot -p wa -k boot"
        "-w /etc/group -p wa -k identity"
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/shadow -p wa -k identity"
        "-w /etc/ssh -p wa -k remote-access"
        "-w /etc/sudoers -p wa -k privilege"
        "-w /sys/firmware/efi/efivars -p wa -k firmware"
      ];
    };
    auditd = {
      enable = true;
      settings = {
        admin_space_left = 1024;
        admin_space_left_action = "suspend";
        disk_error_action = "suspend";
        disk_full_action = "suspend";
        max_log_file = 256;
        max_log_file_action = "rotate";
        num_logs = 16;
        space_left = 2048;
        space_left_action = "syslog";
      };
    };
    protectKernelImage = true;
    lockKernelModules = true;
  };

  systemd = {
    services.auditd = {
      reloadIfChanged = true;
      restartTriggers = [ config.environment.etc."audit/auditd.conf".source ];
      serviceConfig.ExecReload = "${config.security.auditd.package}/bin/auditctl --signal reload";
    };
    services.audit-resume = {
      description = "Resume audit logging after disk space recovers";
      requires = [ "auditd.service" ];
      after = [ "auditd.service" ];
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.coreutils
        pkgs.gawk
      ];
      script = ''
        available=$(df --output=avail -k /var/log/audit | awk 'NR == 2 { print $1 }')
        if [ "$available" -ge 2097152 ]; then
          ${config.security.auditd.package}/bin/auditctl --signal resume
        else
          echo "audit logging recovery deferred: less than 2 GiB free" >&2
          exit 1
        fi
      '';
    };
    timers.audit-resume = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };
    sleep.settings.Sleep = {
      AllowHibernation = false;
      AllowHybridSleep = false;
      AllowSuspend = false;
      AllowSuspendThenHibernate = false;
    };
    services.systemd-coredump.enable = false;
  };

  services.journald.extraConfig = ''
    Compress=yes
    Seal=yes
    Storage=persistent
    SystemMaxUse=2G
  '';
}
