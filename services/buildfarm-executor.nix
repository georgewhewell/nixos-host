{
  config,
  lib,
  ...
}: {
  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    settings = {
      # trusted-builders = ["ssh-ng://grw@trex.satanic.link"];
      # extra-substituters = ["ssh-ng://grw@trex.satanic.link"];
      # trusted-substituters = ["ssh-ng://grw@trex.satanic.link"];
    };
    buildMachines =
      [
        {
          hostName = "rock-5b.satanic.link";
          sshUser = "grw";
          speedFactor = 2;
          maxJobs = 4;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel"];
          systems = ["aarch64-linux"];
        }
        {
          hostName = "ax102.lsd-ag.ch";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 4;
          speedFactor = 64;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel" "cuda" "gccarch-znver4"];
          systems = [
            "x86_64-linux"
            "i686-linux"
          ];
        }
      ]
      ++ lib.optionals (config.networking.hostName != "trex") [
/*        {
          hostName = "trex.satanic.link";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 8;
          speedFactor = 128;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel" "cuda" "gccarch-znver4"];
          systems = [
            "x86_64-linux"
            "i686-linux"
          ];
          }
          */
      ];
  };
}
