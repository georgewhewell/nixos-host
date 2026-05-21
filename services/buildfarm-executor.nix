{
  config,
  lib,
  network,
  ...
}: {
  # SSH host keys for build machines (needed for nix-daemon which has no HOME)
  programs.ssh.knownHosts = {
    ${network.domains.public}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZf+7YvQNvTBGe9FtSeXr+Z7EUYeulTQEkfqlbO8C6/";
    ${network.fqdn "fuckup"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAiyQ6dBe9MCPVf5zQkfaCWFTT63Ke3Vdtj5ZCsgkplQ";
    ${network.fqdn "strix-2"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID0RsY9sp58nDjojVM9uAZ+6DoLxi/8LrGuonSoSC2DS";
    "ax102.lsd-ag.ch".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAmZe5wTNNkmTuqMsRvmnN6LZMdKmwcnW79PyrsDZS4K";
    ${network.fqdn "rock-5b"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKybhRhji8rxnMqDDAvDwnqepqu6hoS67XgchouMzYk2";
    ${network.fqdn "strix-1"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPHXYxvg1N//t89I4vktqPKg4yGgI5amT97GHt3mHStV";
    ${network.fqdn "trex"}.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5OnThSY2XWfeAeRnB/HcPFHKS43ToDavxKBwGxP6lj";
    "mbp".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEn8GwjuFsx8r3wXq0J28mHg2WZdbo4NH45bxg9EwSTO";
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
    };
    buildMachines =
      [
        {
          hostName = network.fqdn "fuckup";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 1;
          speedFactor = 48;
          supportedFeatures = ["gccarch-znver5" "rocm" "rtx4090" "9950x3d" "kvm" "nixos-test" "big-parallel"];
          systems = [
            "x86_64-linux"
            "i686-linux"
          ];
        }
        {
          hostName = network.fqdn "strix-2";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 1;
          speedFactor = 32;
          supportedFeatures = ["gccarch-znver5" "rocm" "gfx1151" "aimax395" "kvm" "nixos-test" "big-parallel"];
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
      ++ lib.optionals (config.networking.hostName != "strix-1") [
        {
          hostName = network.fqdn "strix-1";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 1;
          speedFactor = 32;
          supportedFeatures = ["gccarch-znver5" "rocm" "gfx1151" "aimax395" "kvm" "nixos-test" "big-parallel"];
          systems = [
            "x86_64-linux"
            "x86_64-windows"
            "i686-linux"
          ];
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
            "aarch64-linux" # via binfmt emulation
          ];
        }
      ]
      ++ lib.optionals (config.networking.hostName != "mbp") [
        {
          hostName = "mbp";
          sshUser = "grw";
          protocol = "ssh-ng";
          maxJobs = 4;
          speedFactor = 64;
          supportedFeatures = ["apple-m4" "big-parallel"];
          systems = ["aarch64-darwin"];
        }
      ];
  };
}
