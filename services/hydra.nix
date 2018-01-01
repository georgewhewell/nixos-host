{ config, lib, pkgs, boot, networking, containers, ... }:

{

  networking.firewall.allowedTCPPorts = [ 3000 ];

  services.hydra = {
    enable = true;
    dbi = "dbi:Pg:dbname=hydra;host=nixhost.4a;user=hydra;password=hydra";
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
       binary_cache_secret_key_file /etc/nix/signing-key.sec
    '';
  };

  nix.distributedBuilds = true;
  nix.buildMachines = [
     {
      hostName = "localhost";
      maxJobs = "12";
      system = "x86_64-linux";
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
    }
    { hostName = "odroid-c2.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
      supportedFeatures = [ "big-parallel" ];
    }
    #{ hostName = "orangepi-prime.4a";
    #  sshUser = "root";
    #  sshKey = "/etc/nix/buildfarm";
    #  system = "aarch64-linux";
    #  maxJobs = 1;
    #  supportedFeatures = [ "big-parallel" ];
    #}
    #{ hostName = "nanopi-m3.4a";
    #  sshUser = "root";
    #  sshKey = "/etc/nix/buildfarm";
    #  system = "aarch64-linux";
    #  maxJobs = 1;
    #  supportedFeatures = [ ];
    #}
 #   { hostName = "orangepi-pc2.4a";
 #     sshUser = "root";
 #     sshKey = "/etc/nix/buildfarm";
 #     system = "aarch64-linux";
 #     maxJobs = 1;
 #     supportedFeatures = [ ];
 #   }
    { hostName = "nanopi-neo2.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
      supportedFeatures = [ ];
    }
 #   { hostName = "raspberrypi-2b.4a";
 #     sshUser = "root";
 #     sshKey = "/etc/nix/buildfarm";
 ##     system = "armv7l-linux";
 #     maxJobs = 1;
 #   }
 #   { hostName = "orangepi-zero.4a";
 #     sshUser = "root";
 #     sshKey = "/etc/nix/buildfarm";
 #     system = "armv7l-linux";
 #     maxJobs = 1;
 #   }
    { hostName = "163.172.191.174";
      speedFactor = 2;
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "armv7l-linux";
      maxJobs = 1;
      supportedFeatures = [ "big-parallel" ];
    }
    { hostName = "orangepi-plus2e.4a";
     speedFactor = 2;
     sshUser = "root";
     sshKey = "/etc/nix/buildfarm";
     system = "armv7l-linux";
     maxJobs = 1;
     supportedFeatures = [ "big-parallel" ];
    }
   # { hostName = "x3399.4a";
   #   speedFactor = 3;
   #   sshUser = "root";
   #   sshKey = "/etc/nix/buildfarm";
   #   system = "aarch64-linux";
   #   maxJobs = 2;
   #   supportedFeatures = [ "big-parallel" ];
   # }
    { hostName = "212.47.251.39";
      speedFactor = 2;
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
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
