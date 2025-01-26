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
          hostName = "192.168.23.18";
          sshUser = "grw";
          speedFactor = 2;
          maxJobs = 8;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel"];
          systems = ["aarch64-linux"];
        }
      ]
      ++ lib.optionals (config.networking.hostName != "trex") [
        {
          hostName = "192.168.23.8";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 8;
          speedFactor = 128;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel" "cuda"];
          systems = [
            "x86_64-linux"
            "i686-linux"
          ];
        }
      ];
  };
}
