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
    /* package = pkgs.hydra.overrideAttrs(old: rec {
        name = "hydra-${version}";
        version = "master";
        src = pkgs.fetchFromGitHub {
          owner = "NixOS";
          repo = "hydra";
          rev = "df27358e11ad09fe3516a4e41d9fe1fd49f911a7";
          sha256 = "0wmd6b8m4ck96ngi768ap5d506xlry68di18rz8das1cns1gyrdi";
        };
    }); */
    extraConfig = ''
      max_output_size = 4294967296
      binary_cache_secret_key_file /etc/nix/signing-key.sec
    '';
  };
  nix.binaryCaches = lib.mkForce [
      https://cache.satanic.link
      /* https://www.cs.helsinki.fi/u/tmtynkky/nixos-arm/channel/ */
  ];
  nix.binaryCachePublicKeys = [
    "hydra.satanic.link-1:U4ZvldOwA3GWLmFTqdXwUu9oS0Qzh4+H/HSl8O6ew5o="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nixos-arm.dezgeg.me-1:xBaUKS3n17BZPKeyxL4JfbTqECsT+ysbDJz29kLFRW0=%"
  ];
  nix.distributedBuilds = true;
  nix.buildMachines = [
     {
      hostName = "localhost";
      maxJobs = "4";
      systems = [ "x86_64-linux" "i686-linux" ];
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
    { hostName = "odroid-c2.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      speedFactor = 3;
      maxJobs = 1;
    }
    { hostName = "rock64.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      speedFactor = 3;
      maxJobs = 1;
    }
    { hostName = "nanopi-m3.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      supportedFeatures = [ "big-parallel" ];
      speedFactor = 2;
      maxJobs = 1;
    }
    { hostName = "pine64-pine64.4a";
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      speedFactor = 1;
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
     supportedFeatures = [ "big-parallel" "highmem" ];
   }
   { hostName = "212.47.251.39";
      speedFactor = 6;
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
  ];

}
