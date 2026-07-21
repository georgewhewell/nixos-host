{
  config,
  lib,
  network,
  ...
}: let
  mkBenchmarkBuilder = name: builder: {
    enable = config.networking.hostName != name;
    hostName = network.fqdn name;
    sshUser = "grw";
    protocol = "ssh-ng";
    inherit
      (builder)
      maxJobs
      speedFactor
      systems
      systemFeatures
      gpus
      ;
    publicKey = builder.publicKey;
  };
in {
  # SSH host keys for build machines (needed for nix-daemon which has no HOME)
  programs.ssh.knownHosts = {
    ${network.domains.public}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZf+7YvQNvTBGe9FtSeXr+Z7EUYeulTQEkfqlbO8C6/";
    ${network.fqdn "fuckup"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAiyQ6dBe9MCPVf5zQkfaCWFTT63Ke3Vdtj5ZCsgkplQ";
    "ax102.lsd-ag.ch".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmZe5wTNNkmTuqMsRvmnN6LZMdKmwcnW79PyrsDZS4K";
    ${network.fqdn "rock-5b"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKybhRhji8rxnMqDDAvDwnqepqu6hoS67XgchouMzYk2";
    ${network.fqdn "trex"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5OnThSY2XWfeAeRnB/HcPFHKS43ToDavxKBwGxP6lj";
  };

  nix = {
    distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';
    settings = {
      # trusted-builders = ["ssh-ng://grw@${network.publicFqdn "trex"}"];
      # extra-substituters = ["ssh-ng://grw@${network.publicFqdn "trex"}"];
      trusted-substituters = ["ssh-ng://grw@${network.publicFqdn "trex"}"];
      # Executors dispatch builds and hold .drv roots — keep their outputs
      # around so repeated builds can substitute locally instead of re-fetching.
      keep-outputs = true;
    };
    buildMachines =
      [
        {
          hostName = network.fqdn "fuckup";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 1;
          speedFactor = 48;
          supportedFeatures = [
            "gccarch-znver5"
            "cuda"
            "benchmark"
            "nvidia"
            "rtx4090"
          ];
          mandatoryFeatures = [
            "benchmark"
            "rtx4090"
          ];
          systems = ["x86_64-linux"];
        }
      ]
      ++ lib.optionals (config.networking.hostName != "rock-5b") [
        {
          hostName = network.fqdn "rock-5b";
          sshUser = "grw";
          protocol = "ssh-ng";
          speedFactor = 1;
          maxJobs = 4;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel"];
          systems = ["aarch64-linux"];
        }
      ]
      ++ lib.optionals (config.networking.hostName != "trex") [
        {
          hostName = network.fqdn "trex";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 1;
          speedFactor = 128;
          supportedFeatures = ["kvm" "nixos-test" "big-parallel" "gccarch-znver4"];
          systems = [
            "x86_64-linux"
            "x86_64-windows"
            "i686-linux"
          ];
        }
      ];
    # mbp flows through benchmark.executor.builders via network.benchmarkBuildHosts.
  };

  benchmark.executor = {
    enable = true;
    builders = lib.mapAttrs mkBenchmarkBuilder network.benchmarkBuildHosts;
  };
}
