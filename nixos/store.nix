{ config, lib, pkgs, ... }:

{
  services.nix-serve = {
    enable = true;
    secretKeyFile = "/etc/nix/signing-key.sec";
  };

  networking.firewall.allowedTCPPorts = [ 3000 ];
  nix.distributedBuilds = true;

  nix.buildMachines = [
    { hostName = "localhost";
      system = "x86_64-linux";
      maxJobs = 2;
    }
    { hostName = "nanopi-m3-nix.4a";
      sshUser = "buildfarm";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
    }
    { hostName = "odroid-c2.4a";
      sshUser = "buildfarm";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
    }
  ];

}
