{
  config,
  pkgs,
  lib,
  inputs,
  localOverlays,
  network,
  ...
}: let
  lanPrefixRegex = builtins.replaceStrings ["."] ["\\."] network.vlans.lan.prefix;
in {
  imports = [
    ./system.nix
    ../../modules/nix.nix
    ../../modules/xmrig-darwin.nix
    inputs.nix-strix-halo.darwinModules.benchmark-executor
    ../../services/buildfarm-executor.nix
    inputs.home-manager.darwinModules.home-manager
    inputs.mac-app-util.darwinModules.default
  ];

  # sops-nix: use SSH host key for decryption
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

  environment.enableAllTerminfo = true;

  security.sudo.extraConfig = ''
    grw ALL=(ALL) NOPASSWD: ALL
  '';

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays =
    [
      inputs.darwin.overlays.default
    ]
    ++ localOverlays;

  users.users."grw" = let
    keys = import ../../profiles/ssh-keys.nix;
  in {
    shell = pkgs.zsh;
    home = "/Users/grw";
    openssh.authorizedKeys.keys = builtins.attrValues keys;
  };

  system.primaryUser = "grw";

  home-manager.useGlobalPkgs = true;
  home-manager.extraSpecialArgs = {inherit inputs network;};
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
      # ollama
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

  # SSH common config is handled by ../../modules/ssh-common.nix
  programs.ssh = {
    extraConfig = ''
      # ProxyJump logic for ${network.domains.public} hosts
      Match host *.${network.domains.public} exec "! (ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -q '${lanPrefixRegex}\.'"
        ProxyJump grw@${network.domains.public}

      # Direct connection when on local network
      Match host *.${network.domains.public} exec "(ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -q '${lanPrefixRegex}\.'"
        ProxyJump none

      # Control master settings
      Host *
        ControlMaster auto
        ControlPath ~/.ssh/control-%r@%h:%p
        ControlPersist 10m
        ServerAliveInterval 60
        ServerAliveCountMax 5
    '';
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    initdbArgs = ["-U grw" "--auth trust"];
  };

  # launchd.user.agents.ollama-serve = {
  #   command = "ollama serve";
  #   path = with pkgs; [ollama];
  #   environment = {
  #     OLLAMA_DEBUG = "1";
  #   };
  #   serviceConfig = {
  #     KeepAlive = true;
  #     RunAtLoad = true;
  #     StandardOutPath = "/tmp/ollama.out.log";
  #     StandardErrorPath = "/tmp/ollama.err.log";
  #   };
  # };

  launchd.user.agents.postgresql.serviceConfig = {
    StandardErrorPath = "/tmp/postgres.error.log";
    StandardOutPath = "/tmp/postgres.log";
  };

  # doesnt work- installed manually
  # launchd.daemons.mullvad-daemon = {
  #   path = with pkgs; [mullvad];
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
  # environment.systemPackages = with pkgs; [
  #   mullvad
  #   # mullvad-vpn
  # ];

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

  # NFS client configuration
  environment.etc."nfs.conf".text = ''
    nfs.client.mount.options = vers=4.0,sec=krb5
    nfs.client.default_nfs4domain = ${network.domains.public}
  '';

  # Core nix settings are in modules/nix.nix
  nix = {
    registry.nixpkgs.flake = inputs.nixpkgs;
    settings = {
      # Darwin-specific
      download-buffer-size = 104857600; # 100 MiB
      http-connections = 32;
      system = "aarch64-darwin";
      system-features = ["apple-virt" "benchmark" "big-parallel" "apple-m4" "metal"];
      max-jobs = "auto";
      build-users-group = "nixbld";
      build-cores = 0;
      builders-use-substitutes = true;
      always-allow-substitutes = true;
      trusted-substituters = [
        "ssh-ng://grw@trex.${network.domains.lan}"
      ];
      trusted-users = [
        "@admin"
        "root"
      ];
      keep-outputs = true; # Dev machine
    };
  };
}
