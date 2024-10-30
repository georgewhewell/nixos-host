{ config, lib, pkgs, ... }:

{
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    # settings = {
    #   extra-substituters = [ "ssh-ng://grw@trex.satanic.link" ];
    #   trusted-substituters = [ "ssh-ng://grw@trex.satanic.link" ];
    # };
    buildMachines = [
      {
        hostName = "rock-5b.satanic.link";
        sshUser = "root";
        speedFactor = 2;
        maxJobs = 2;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [ "aarch64-linux" ];
      }
    ] ++ lib.optionals (config.networking.hostName != "trex") [
      {
        hostName = "trex.satanic.link";
        sshUser = "grw";
        protocol = "ssh-ng";
        maxJobs = 16;
        speedFactor = 128;
        supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
        systems = [
          "x86_64-linux"
          "i686-linux"
        ];
      }
    ];
  };
}
