{ config, pkgs, lib, ... }:

{
  /*
    fuckup: skylake desktop
  */

  imports =
    [
      ./containers/plex.nix
      ./profiles/common.nix
      ./profiles/development.nix
      ./profiles/bridge-interfaces.nix
      ./profiles/home.nix
      ./profiles/nas-mounts.nix
      ./profiles/uefi-boot.nix
      ./profiles/g_ether.nix
      ./profiles/xserver.nix
      ./profiles/intel-gfx.nix
      ./services/docker.nix
      ./services/virt/host.nix
      ./services/virt/vfio.nix
    ];

  fileSystems."/" =
    { device = "zpool/root/nixos-fuckup";
      fsType = "zfs";
    };

  fileSystems."/home/grw" =
    { device = "zpool/root/grw";
      fsType = "zfs";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/CD68-6C43";
      fsType = "vfat";
    };

  boot.kernelModules = [ "wl" ];
  boot.blacklistedKernelModules = [
    "b44" "b43" "b43legacy" "ssb" "brcmsmac" "bcma" ];
  boot.extraModulePackages = [
    config.boot.kernelPackages.broadcom_sta
  ];

  system.stateVersion = "18.03";

  nix.maxJobs = lib.mkDefault 8;
  powerManagement.cpuFreqGovernor = "performance";

  environment.systemPackages = with pkgs; [
    steam
    nixops
  ];

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCoqpsUUtxaO0QzI9MxCs5tRjsbORDwpjFjuUFdGHJwZqm7A2MzrRV7EKfqfolgxnyaAFs7IM9AZ7o9Lus2MWX89c4OAW0upeoj2qsXMiFZH7z50Cdmg/YMw5DtVMZwPBTl0S1COWfhw959QntlTjhcYh3usIq9b3XeTELGtJSk5RmTjPIA2LJ4cemx3Ru11SySvk0LsI3uCv0Vhy9n17g1sg5eekRs5Nvg1AJtOQcH4Du/0rUwwEDd9Zjn0YiF/uPVMVh22JzWVE5dbe81g8dw+mR6GRnN3vlYbU+JgGvMKgs2DeGvPHSJWl9rwKUVO6wuruzZH+1q2HxAr58ndz81 root@nixhost"
  ];

  networking = {
    hostName = "fuckup.lan";
    hostId = "deadbeef";
    useDHCP = true;
    wireless.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 9100 10809 8880 ];
      checkReversePath = false;
    };

    bridges.br0 = {
      interfaces = [
        "enp0s31f6" # onboard ethernet
        "enp1s0f0"  # sfp+
        "enp1s0f1"  # sfp+
      ];
    };
  };

  services.consul.extraConfig = {
    server = true;
  };
  services.consul.interface =
    let interface = "br0"; in {
      advertise = interface;
      bind = interface;
    };

  services.xserver = {
    useGlamor = false; # off is tearing; on is lag
    videoDrivers = [ "modesetting" ];
    xrandrHeads = [
      { output = "DP-1"; primary = true; monitorConfig = ''
        # 3440x1440 @ 75.05 Hz (GTF) hsync: 112.80 kHz; pclk: 534.22 MHz
        Modeline "3440x1440_75.00"  533.87  3440 3712 4088 4736  1440 1441 1444 1503  -HSync +Vsync
        Option "PreferredMode" "3440x1440_75.00"
        Option "Broadcast RGB" "Full"
    '';}
    ];
  };

  virtualisation.kvmgt = {
    enable = true;
    vgpus = {
      "i915-GVTg_V5_4" = {
        uuid = "a297db4a-f4c2-11e6-90f6-d3b88d6c9525";
      };
    };
  };

  services.redshift = {
    enable = true;
    latitude = "51.5";
    longitude = "0";

    brightness = {
      day = "1.0";
      night = "0.6";
    };
  };

  services.fwupd.enable = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
  };
}
