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
      trusted-substituters = ["ssh-ng://grw@trex.satanic.link"];
    };
    buildMachines =
      [
        {
          hostName = "fuckup.lan.satanic.link";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 2;
          speedFactor = 64;
          supportedFeatures = ["gccarch-znver5"];
          systems = [
            "x86_64-linux"
            "i686-linux"
          ];
        }
        {
          hostName = "strix-1.lan.satanic.link";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 2;
          speedFactor = 64;
          supportedFeatures = ["gccarch-znver5" "rocm" "gfx1151" "kvm" "nixos-test" "big-parallel"];
          systems = [
            "x86_64-linux"
            # "i686-linux"
          ];
        }
        {
          hostName = "strix-2.lan.satanic.link";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 2;
          speedFactor = 64;
          supportedFeatures = ["gccarch-znver5" "rocm" "gfx1151" "kvm" "nixos-test" "big-parallel"];
          systems = ["x86_64-linux"];
        }
        {
          hostName = "ax102.lsd-ag.ch";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 3;
          speedFactor = 64;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel" "gccarch-znver4"];
          systems = [
            "x86_64-linux"
            "i686-linux"
          ];
        }
      ]
      ++ lib.optionals (config.networking.hostName != "rock-5b") [
        {
          hostName = "rock-5b.lan.satanic.link";
          sshUser = "grw";
          protocol = "ssh-ng";
          speedFactor = 2;
          maxJobs = 4;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel"];
          systems = ["aarch64-linux"];
        }
        # {
        #   hostName = "prime.lan.satanic.link";
        #   sshUser = "grw";
        #   protocol = "ssh-ng";
        #   speedFactor = 1;
        #   maxJobs = 1;
        #   supportedFeatures = ["nixos-test"];
        #   systems = ["aarch64-linux"];
        # }
      ]
      ++ lib.optionals (config.networking.hostName != "trex") [
        {
          hostName = "trex.satanic.link";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 6;
          speedFactor = 128;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel" "gccarch-znver4"];
          systems = [
            "x86_64-linux"
            "x86_64-windows"
            "i686-linux"
          ];
        }
      ];
  };
}
