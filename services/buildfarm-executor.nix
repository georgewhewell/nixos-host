{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    buildMachines = [
      {
        hostName = "george.kaki.dev";
        sshUser = "grw";
        maxJobs = 4;
        speedFactor = 12;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "x86_64-linux" "i686-linux" ];
      }
      {
        hostName = "rock-5b";
        sshUser = "root";
        speedFactor = 2;
        maxJobs = 2;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
      {
        hostName = "air";
        sshUser = "root";
        speedFactor = 4;
        maxJobs = 2;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
    ];
  };
}
