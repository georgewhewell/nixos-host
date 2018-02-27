{ config, lib, pkgs, boot, networking, containers, ... }:

{

  networking.firewall.allowedTCPPorts = [ 3000 ];
  systemd.services."hydra-init".after = [ "network-online.target" ];

  services.hydra = {
    enable = true;
    dbi = "dbi:Pg:dbname=hydra;host=192.168.23.5;user=hydra;password=hydra";
    hydraURL = "https://hydra.satanic.link/";
    listenHost = "0.0.0.0";
    port = 3000;
    minimumDiskFree = 5;  # in GB
    minimumDiskFreeEvaluator = 2;
    notificationSender = "hydra@satanic.link";
    logo = null;
    debugServer = false;
    useSubstitutes = true;
    extraConfig = ''
      max_output_size = 4294967296
      binary_cache_secret_key_file /etc/nix/signing-key.sec
    '';
  };
  nix.binaryCaches = lib.mkForce [
      https://cache.satanic.link/
  ];
  nix.distributedBuilds = true;
  nix.buildMachines = [
     {
      hostName = "localhost";
      maxJobs = "4";
      systems = ["x86_64-linux" "i686-linux"];
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
    }
    {
      hostName = "fuckup.4a";
      maxJobs = "4";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      systems = ["x86_64-linux" "i686-linux"];
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
    }
    { hostName = "rock64.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
      supportedFeatures = [ "big-parallel" ];
    }
    { hostName = "odroid-c2.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
    }
    { hostName = "raspberrypi-2b.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "armv7l-linux";
      maxJobs = 1;
    }
    { hostName = "orangepi-zero.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "armv7l-linux";
      maxJobs = 1;
    }
    { hostName = "orangepi-plus2e.4a";
     speedFactor = 2;
     sshUser = "root";
     sshKey = "/etc/nix/buildfarm";
     system = "armv7l-linux";
     maxJobs = 1;
    }
    { hostName = "51.15.195.104";
     speedFactor = 4;
     sshUser = "root";
     sshKey = "/etc/nix/buildfarm";
     system = "armv7l-linux";
     maxJobs = 1;
     supportedFeatures = [ "big-parallel" ];
   }
   { hostName = "212.47.251.39";
      speedFactor = 2;
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
      supportedFeatures = [ "big-parallel" ];
    }
   {
      hostName = "odroidxu4.4a";
      speedFactor = 6;
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "armv7l-linux";
      maxJobs = 1;
      supportedFeatures = [ "big-parallel" ];
    }
    { hostName = "jetson-tx1.4a";
      speedFactor = 3;
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
      supportedFeatures = [ "big-parallel" ];
    }
  ];

}
