{ config, lib, pkgs, ... }:

{
  /*
    NVIDIA 980 Ti / Intel z170 Skylake

    lsgroups.sh:

    VFIO? ### Group 0 ###
    00:00.0 Host bridge [0600]: Intel Corporation Sky Lake Host Bridge/DRAM Registers [8086:191f] (rev 07)
    ### Group 1 ###
    00:01.0 PCI bridge [0604]: Intel Corporation Sky Lake PCIe Controller (x16) [8086:1901] (rev 07)
    Y         01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM200 [GeForce GTX 980 Ti] [10de:17c8] (rev a1)
    Y         01:00.1 Audio device [0403]: NVIDIA Corporation Device [10de:0fb0] (rev a1)
    ### Group 2 ###
    ?         00:02.0 VGA compatible controller [0300]: Intel Corporation Sky Lake Integrated Graphics [8086:1912] (rev 06)
    ### Group 3 ###
    ?         00:14.0 USB controller [0c03]: Intel Corporation Sunrise Point-H USB 3.0 xHCI Controller [8086:a12f] (rev 31)
    00:14.2 Signal processing controller [1180]: Intel Corporation Sunrise Point-H Thermal subsystem [8086:a131] (rev 31)
    ### Group 4 ###
    00:16.0 Communication controller [0780]: Intel Corporation Sunrise Point-H CSME HECI #1 [8086:a13a] (rev 31)
    ### Group 5 ###
    ?         00:17.0 SATA controller [0106]: Intel Corporation Device [8086:a102] (rev 31)
    ### Group 6 ###
    00:1c.0 PCI bridge [0604]: Intel Corporation Sunrise Point-H PCI Express Root Port #1 [8086:a110] (rev f1)
    00:1c.4 PCI bridge [0604]: Intel Corporation Sunrise Point-H PCI Express Root Port #5 [8086:a114] (rev f1)
    00:1c.6 PCI bridge [0604]: Intel Corporation Sunrise Point-H PCI Express Root Port #7 [8086:a116] (rev f1)
    Y         03:00.0 USB controller [0c03]: ASMedia Technology Inc. ASM1142 USB 3.1 Host Controller [1b21:1242]
    Y         04:00.0 Network controller [0280]: Broadcom Corporation BCM4352 802.11ac Wireless Network Adapter [14e4:43b1] (rev 03)
    ### Group 7 ###
    00:1d.0 PCI bridge [0604]: Intel Corporation Sunrise Point-H PCI Express Root Port #9 [8086:a118] (rev f1)
    Y         05:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd Device [144d:a802] (rev 01)
    ### Group 8 ###
    00:1f.0 ISA bridge [0601]: Intel Corporation Sunrise Point-H LPC Controller [8086:a145] (rev 31)
    00:1f.2 Memory controller [0580]: Intel Corporation Sunrise Point-H PMC [8086:a121] (rev 31)
    Y         00:1f.3 Audio device [0403]: Intel Corporation Sunrise Point-H HD Audio [8086:a170] (rev 31)
    00:1f.4 SMBus [0c05]: Intel Corporation Sunrise Point-H SMBus [8086:a123] (rev 31)
    ?         00:1f.6 Ethernet controller [0200]: Intel Corporation Ethernet Connection (2) I219-V [8086:15b8] (rev 31)
  */
  environment.systemPackages = [ pkgs.scream ];

  boot.blacklistedKernelModules = [
    "nouveau"
    "nvidia"
    "b43"
    #  "amdgpu"
  ];

  boot.kernelParams = [
    # amdgpu passthrough
    "vfio-pci.ids=1002:731f,1002:ab38"
    "pcie_acs_override=downstream,multifunction"
    "video=efifb:off"
    "hugepagesz=1GB"
    "default_hugepagesz=1G"
    "hugepages=16"
    "transparent_hugepages=never"
  ];

  systemd.mounts = [
    # disable mounting hugepages by systemd,
    # it doesn't know about 1G pagesize
    {
      where = "/dev/hugepages";
      enable = false;
    }
    {
      where = "/dev/hugepages/hugepages-1048576kB";
      enable = true;
      what = "hugetlbfs";
      type = "hugetlbfs";
      options = "pagesize=1G";
      requiredBy = [ "basic.target" ];
    }
  ];

  environment.etc."tmpfiles.d/thp.conf".text = ''
    w /sys/kernel/mm/transparent_hugepage/enabled         - - - - never
  '';

  boot.kernel.sysctl = {
    "vm.nr_hugepages" = lib.mkForce 16;
  };

  boot.kernelPatches = [
    { name = "acs-overrides"; patch = ./add-acs-overrides.patch; }
    { name = "i915-vga-arbiter"; patch = ./i915-vga-arbiter.patch; }
  ];

  boot.extraModulePackages = [
    config.boot.kernelPackages.vendor-reset
  ];

  networking.firewall.allowedUDPPorts = [ 1567 4010 ];

  systemd.services.scream-receiver = {
    wantedBy = [ "libvirtd.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.scream}/bin/scream";
      User = "grw";
      Group = "audio";
    };
  };

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_5_18;
}
