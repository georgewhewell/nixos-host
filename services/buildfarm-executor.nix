{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    buildMachines = [
    {
        hostName = "/nix/store";
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        maxJobs = 4;
        systems = [ "builtin" "x86_64-linux" "i686-linux" ];
    }
    {
        hostName = "nixhost.lan";
        sshUser = "root";
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        maxJobs = 8;
        speedFactor = 1;
        systems = ["x86_64-linux" "i686-linux"];
      }
      {
        hostName = "odroid-c2.lan";
        sshUser = "root";
        speedFactor = 2;
        supportedFeatures = [ "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
      {
        hostName = "rock64.lan";
        sshUser = "root";
        speedFactor = 2;
        supportedFeatures = [ "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
      {
        hostName = "odroid-hc1.lan";
        sshUser = "root";
        speedFactor = 2;
        supportedFeatures = [ "big-parallel" ];
        systems = [ "armv7l-linux" ];
      }
    ];
  };
}
