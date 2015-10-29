{ config, lib, pkgs, ... }:

{
  networking.hostName = "nixhost";
  time.timeZone = "Europe/London";
  networking.firewall.enable = false;

  i18n = {
    consoleFont = "Lat2-Terminus16";
    defaultLocale = "en_GB.UTF-8";
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    iptables
    virtmanager
    OVMF
    firefox
    gnome3.dconf
  ];

  security.sudo.wheelNeedsPassword = false;

  services.avahi.enable = true;
  services.avahi.nssmdns = true;
  services.openssh.enable = true;

  # looks like passthu wont work
  # services.xserver.enable = true;
  # services.xserver.desktopManager.xfce.enable = true;

  fileSystems."/boot" =
    { device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_2TB_S2HDNWAG701220D-part1";
      fsType = "vfat";
    };

  fileSystems."/" =
    { device = "/dev/disk/by-id/dm-name-evo-nixos";
      fsType = "btrfs";
    };

  fileSystems."/storage" =
    { device = "/dev/disk/by-id/dm-name-evo-storage";
      fsType = "btrfs";
    };

  imports = [
    <nixpkgs/nixos/modules/installer/scan/not-detected.nix>
    ./hardware/efiboot.nix

    ./kernels/4_1.nix

    ./network/wlan.nix

    ./nixos/16_03.nix

    ./services/nfs.nix
    ./services/virt/host.nix

    ./users.nix
  ];
}
