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
    ../../../profiles/luks-yubi.nix
    ../../../profiles/thinkpad.nix
    ../../../services/docker.nix
  ];

  networking.hostName = "yoga";
  networking.hostId = "deadbeef";

  # deployment.targetHost = "nixos-installer";

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      efiSupport = true;
      device = "nodev";
    };  
  };

  virtualisation.docker.storageDriver = lib.mkForce null;
  
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.initrd.network = { 
    enable = true;
    ssh = {
      enable = true;
      port = 22;
      authorizedKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC33L+epirAZn22pRF0i/+618qWprG121KVZqPjLkpMRhsGrF1zmUnvTYEaJfg6ZD9Ndrnw5XfGw9iazkxs55JFnm+qzv9DIWjIVMTH9QLDEscz7bY0df5wKOtInByLAQ0g7KoZIZugMjywU5+N42PztUQ7fdt90tYZm4hvg7ZrjjbQBHAn3dwAsqmyQ3BtSiqfoudRABEwZx1pRqZrIE1Ms6xOHT4WN1cPCL0ROG1BWY148dj05nhJl9wGgqgFGkJoxb4bdfDsPqtcveGIFKQo5bb66OOsulSJdDA5MberYrrN8sD/yWcuwi/arRqwFAAU6MRMsM+7g5AAauNXoZVJnX0ltf2cyajUjCrLLcVSvebzH1m1ZvVqeqjUagXnc6wWpOv8NmVJMcfoboYWJ1dRfGaoUAX/T9joFr87fWkOvd/cuxRhUcy5IbL/o1ykhAfmaSUlFmdOkms8WEOwkJ+5tmRwkfSTWYwFMQcqJgf/PepatWYW/ruUTFwRDVLRx6+EdH1EiVpYCd+F2OgSUsaH7kvafciVZbwFwpg51BQ9uCTxavsGZK8TrIK1Mq0ByhOUM8Slk4QNNcIaCXivJpxd5VY2Ak44VgVze0mrxTfYffnDfAFNTmDe7W5E+X36TwqxJXpAiam3vbq8BmpQtSfUyGhWY/0acvfrdCuK9V/JCQ== cardno:000608755089"
      ];
      hostKeys = [ "/etc/nixos/secrets/nixos-secrets/initrd/ssh_host_ed25519_key" ];
    };
    postCommands = ''
      echo "post network"
    '';
  };

  fileSystems."/" =
    {
      device = "/dev/mapper/vg0-nixos";
      fsType = "ext4";
    };

  fileSystems."/home/grw" =
    {
      device = "/dev/mapper/vg0-home";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    {
      device = "/dev/nvme0n1p1";
      fsType = "vfat";
    };

  # swapDevices = [{ device = "/dev/mapper/vg0-swap"; }];

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
