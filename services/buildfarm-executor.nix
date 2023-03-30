{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    buildMachines = [
      # {
      #   hostName = "nixhost.lan";
      #   sshUser = "root";
      #   supportedFeatures = [ "kvm" "nixos-test" ];
      #   maxJobs = 8;
      #   speedFactor = 4;
      #   systems = [ "x86_64-linux" "i686-linux" "aarch64-linux" "armv7l-linux" ];
      # }
      {
        hostName = "ax101.satanic.link";
        sshUser = "root";
        maxJobs = 4;
        speedFactor = 4;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "x86_64-linux" "i686-linux" ];
      }
      {
        hostName = "rock5b";
        sshUser = "grw";
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
      # {
      #   hostName = "odroid-hc1.lan";
      #   sshUser = "root";
      #   maxJobs = 1;
      #   speedFactor = 4;
      #   supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      #   systems = [ "armv7l-linux" ];
      # }
    ];
  };
}
