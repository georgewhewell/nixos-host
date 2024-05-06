{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    buildMachines = [
      {
        hostName = "192.168.23.8";
        sshUser = "grw";
        maxJobs = 16;
        speedFactor = 32;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "x86_64-linux" "i686-linux" ];
      }
      # {
      #   hostName = "rock-5b.lan";
      #   sshUser = "root";
      #   speedFactor = 2;
      #   maxJobs = 2;
      #   supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      #   systems = [ "aarch64-linux" ];
      # }
      # {
      #   hostName = "air.lan";
      #   sshUser = "root";
      #   speedFactor = 4;
      #   maxJobs = 2;
      #   supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      #   systems = [ "aarch64-linux" ];
      # }
    ];
  };
}
