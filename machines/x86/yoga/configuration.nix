{ config, pkgs, lib, ... }:

{

  imports = [
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/home-manager.nix
    ../../../profiles/nas-mounts.nix
    ../../../profiles/development.nix
    ../../../profiles/graphical.nix
    ../../../profiles/intel-gfx.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/thinkpad.nix
    ../../../services/docker.nix
  ];

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";

  virtualisation.docker.storageDriver = lib.mkForce null;
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  fileSystems."/" =
    {
      device = "/dev/mapper/vg1-nixos";
      fsType = "f2fs";
    };

  fileSystems."/home/grw" =

    {
      device = "/dev/mapper/vg1-home";
      fsType = "f2fs";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  swapDevices = [{ device = "/dev/nvme0n1p2"; }];

  nix.maxJobs = lib.mkDefault 4;

  console.font = lib.mkForce "${pkgs.terminus_font}/share/consolefonts/ter-u28n.psf.gz";

  boot.loader.timeout = 1;
  boot.blacklistedKernelModules = [
    "mei"
    "mei_me"
    "mei_wdt"
    "acer_wmi"
    "applesmc"
    "intel_backlight"
  ];

  services.undervolt = {
    enable = true;
    tempAc = 97;
    tempBat = 75;
    coreOffset = -115;
    gpuOffset = -60;
    uncoreOffset = -60;
    analogioOffset = -60;
  };

  networking.wireguard = {
    interfaces = {
      "wg0-cloud" = {
	ips = [ "192.168.24.3/24" ];
	listenPort = 51820;
	privateKey = pkgs.secrets.wg-yoga-priv;
	peers = [
	  {
	    publicKey = pkgs.secrets.wg-router-pub;
	    allowedIPs = [ "192.168.23.0/24" "192.168.24.0/24" ];
	    endpoint = "home.satanic.link:51820";
	    persistentKeepalive = 25;
	  }
	  {
	    publicKey = pkgs.secrets.wg-hetzner-pub;
	    allowedIPs = [ "192.168.24.0/24" ];
	    endpoint = "cloud.satanic.link:51820";
	    persistentKeepalive = 25;
	  }
	];
      };
      "wg1-swaps" = {
	ips = [ "192.168.25.5/24" ];
	listenPort = 51821;
	privateKey = pkgs.secrets.wg-yoga-priv;
	peers = [
	  {
	    publicKey = pkgs.secrets.wg-swaps-router-pub;
	    allowedIPs = [ "192.168.25.0/24" "192.168.23.0/24" ];
	    endpoint = "home.satanic.link:51821";
	    persistentKeepalive = 25;
	  }
	  {
	    publicKey = pkgs.secrets.wg-swaps-hetzner-pub;
	    allowedIPs = [ "192.168.25.0/24" ];
            endpoint = "116.202.128.94:51821";
	    persistentKeepalive = 25;
	  }
	];
      };
    };
  };

}
