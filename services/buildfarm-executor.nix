{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "nixhost.lan";
        sshUser = "root";
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        maxJobs = 2;
        speedFactor = 1;
        systems = [ "x86_64-linux" "i686-linux" ];
      }
      {
        hostName = "odroid-c2.lan";
        sshUser = "root";
        speedFactor = 3;
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
      /* {
        hostName = "amlogic-s912.lan";
        sshUser = "root";
        speedFactor = 1;
        supportedFeatures = [ "big-parallel" ];
        systems = [ "aarch64-linux" ];
      } */
      {
        hostName = "odroid-hc1.lan";
        sshUser = "root";
        speedFactor = 4;
        supportedFeatures = [ "big-parallel" ];
        systems = [ "armv7l-linux" ];
      }
      {
        hostName = "bananapi-m3.lan";
        sshUser = "root";
        speedFactor = 1;
        supportedFeatures = ["big-parallel" ];
        systems = [ "armv7l-linux" ];
      }
      {
        hostName = "orangepi-plus2e.lan";
        sshUser = "root";
        speedFactor = 1;
        supportedFeatures = [ ];
        systems = [ "armv7l-linux" ];
      }
    ];
  };
}
