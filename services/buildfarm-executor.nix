{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    buildMachines = [
      {
        hostName = "trex.satanic.link";
        sshUser = "grw";
        protocol = "ssh-ng";
        maxJobs = 16;
        speedFactor = 128;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "x86_64-linux" "i686-linux" "aarch64-linux" ];
      }
      {
        hostName = "rock-5b.satanic.link";
        sshUser = "root";
        speedFactor = 2;
        maxJobs = 2;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
      {
        hostName = "air.satanic.link";
        sshUser = "grw";
        speedFactor = 4;
        maxJobs = 2;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
    ];
  };
}
