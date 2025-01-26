{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./system.nix
    ../../services/buildfarm-executor.nix
  ];

  nixpkgs.config.allowUnfree = true;

  nix-homebrew = {
    # Install Homebrew under the default prefix
    enable = false;

    # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
    enableRosetta = false;

    # User owning the Homebrew prefix
    user = "grw";

    # Optional: Declarative tap management
    # taps = with inputs; {
    #   "homebrew/homebrew-core" = homebrew-core;
    #   "homebrew/homebrew-cask" = homebrew-cask;
    #   "homebrew/homebrew-bundle" = homebrew-bundle;
    #   # "homebrew/homebrew-discord" = homebrew-discord;
    # };

    # Optional: Enable fully-declarative tap management
    #
    # With mutableTaps disabled, taps can no longer be added imperatively with `brew tap`.
    mutableTaps = false;
  };

  users.users."grw" = {
    shell = pkgs.zsh;
    home = "/Users/grw";
  };

  home-manager.users.grw = {...}: {
    imports = [
      ../../home/common.nix
      ../../home/gpg.nix
      ../../home/development.nix
      ../../home/desktop-apps.nix
      ../../home/darwin.nix
      ../../home/vscode.nix
      ../../home/zed.nix
    ];

    xdg.dataFile."postgresql/.keep".text = "";

    home.packages = with pkgs; [
      ollama
      keybase
      kbfs
    ];
    # homebrew packages
    # homebrew-cask packages
    # home.packages
  };

  launchd.user.agents.keybase = {
    command = "${pkgs.keybase}/bin/keybase service --auto-forked";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/keybase.out.log";
      StandardErrorPath = "/tmp/keybase.err.log";
    };
  };

  programs.ssh = {
    extraConfig = ''
      Host trex.satanic.link
          # StrictHostKeyChecking no
          # User grw
          # IdentityFile ~/.ssh/id_ed25519
          # ControlMaster auto
          ControlPath ~/.ssh/control-%r@%h:%p
          ControlPersist 10m
          ServerAliveInterval 60
    '';
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    initdbArgs = ["-U grw" "--auth trust"];
  };

  launchd.user.agents.ollama-serve = {
    command = "${pkgs.ollama}/bin/ollama serve";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/ollama.out.log";
      StandardErrorPath = "/tmp/ollama.err.log";
    };
  };

  launchd.user.agents.postgresql.serviceConfig = {
    StandardErrorPath = "/tmp/postgres.error.log";
    StandardOutPath = "/tmp/postgres.log";
  };

  system.activationScripts.preActivation = {
    enable = true;
    text = ''
      if [ ! -d "${config.services.postgresql.dataDir}" ]; then
        echo "creating PostgreSQL data directory..."
        sudo mkdir -m 750 -p ${config.services.postgresql.dataDir}
        chown -R grw:staff ${config.services.postgresql.dataDir}
      fi
    '';
  };

  # Used for backwards compatibility, please read the changelog before changing.
  system.stateVersion = 3;
  services.nix-daemon.enable = true;

  programs.zsh.enable = true;

  nix = {
    nixPath = ["nixpkgs=${inputs.nixpkgs}"]; # Enables use of `nix-shell -p ...` etc
    registry.nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs

    optimise.automatic = true;

    settings = {
      system = "aarch64-darwin";
      extra-substituters = ["https://cache.flakehub.com"];
      max-jobs = "auto";
      build-users-group = "nixbld";
      experimental-features = ["nix-command" "flakes"];
      build-cores = 0;
      always-allow-substitutes = true;
      trusted-users = [
        "@admin"
        "grw"
        "root"
      ];
    };
  };
}
