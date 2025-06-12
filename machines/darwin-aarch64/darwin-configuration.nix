{
  config,
  pkgs,
  inputs,
  localOverlays,
  ...
}: {
  imports = [
    ./system.nix
    ../../services/buildfarm-executor.nix
    inputs.home-manager.darwinModules.home-manager
    inputs.mac-app-util.darwinModules.default
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.darwin.overlays.default
  ] ++ localOverlays;

  users.users."grw" = {
    shell = pkgs.zsh;
    home = "/Users/grw";
  };

  system.primaryUser = "grw";

  home-manager.useGlobalPkgs = true;
  home-manager.users.grw = {...}: {
    imports = [
      ../../home/common.nix
      ../../home/gpg.nix
      ../../home/development.nix
      ../../home/desktop-apps.nix
      ../../home/darwin.nix
      ../../home/vscode.nix
      ../../home/zed.nix
      inputs.mac-app-util.homeManagerModules.default
    ];

    xdg.dataFile."postgresql/.keep".text = "";

    home.packages = with pkgs; [
      ollama
      keybase
      kbfs
    ];
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
      Host github.com *.github.com
          ProxyJump none

      Match host "*.satanic.link" exec "ifconfig | grep -q '192.168.23.'"
          ProxyJump none

      Match host "*.satanic.link" exec "! (ifconfig | grep -q '192.168.23.')"
          ProxyJump grw@satanic.link

      Host *
          ControlPath ~/.ssh/control-%r@%h:%p
          ControlPersist 10m
          ControlMaster auto
          ServerAliveInterval 60
    '';
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    initdbArgs = ["-U grw" "--auth trust"];
  };

  launchd.user.agents.ollama-serve = {
    command = "ollama serve";
    path = with pkgs; [ollama];
    environment = {
      OLLAMA_DEBUG = "1";
    };
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

  # launchd.daemons.mullvad-daemon = {
  #   path = with pkgs; [ mullvad ];
  #   command = "mullvad-daemon -v --disable-stdout-timestamps --disable-log-to-file";
  #   serviceConfig = {
  #     Label = "com.mullvad.daemon";
  #     RunAtLoad = true;
  #     KeepAlive = true;
  #     StandardOutPath = "/var/log/mullvad-daemon.log";
  #     StandardErrorPath = "/var/log/mullvad-daemon.error.log";
  #     UserName = "root";
  #   };
  # };

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

  programs.zsh.enable = true;

  nix = {
    nixPath = ["nixpkgs=${inputs.nixpkgs}"]; # Enables use of `nix-shell -p ...` etc
    registry.nixpkgs.flake = inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs
    optimise.automatic = true;
    settings = {
      system = "aarch64-darwin";
      max-jobs = "auto";
      build-users-group = "nixbld";
      experimental-features = ["nix-command" "flakes"];
      build-cores = 0;
      always-allow-substitutes = true;
      download-buffer-size = 500000000;
      trusted-users = [
        "@admin"
        "grw"
        "root"
      ];
    };
  };
}
