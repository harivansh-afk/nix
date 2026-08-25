{ lib, ... }:
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
        admin_space_left = "5%";
        admin_space_left_action = "suspend";
        disk_error_action = "suspend";
        disk_full_action = "suspend";
        max_log_file = 256;
        max_log_file_action = "keep_logs";
        space_left = "10%";
        space_left_action = "syslog";
      };
    };
    protectKernelImage = true;
    lockKernelModules = true;
  };

  systemd = {
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
