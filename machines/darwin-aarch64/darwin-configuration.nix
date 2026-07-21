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
  trexIp = network.primaryIp network.hosts.trex;
  mntSynthetic = "mnt\tSystem/Volumes/Data/mnt";
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

  # Prometheus node_exporter (host metrics) on macOS — node_exporter supports a
  # darwin subset (cpu, loadavg, meminfo, filesystem, netdev, thermal, …). Run as
  # a system daemon on :9100 so trex's VictoriaMetrics scrapes it like the linux
  # nodes. Root daemon → exempt from Local Network Privacy.
  launchd.daemons.node-exporter = {
    command = "${pkgs.prometheus-node-exporter}/bin/node_exporter --web.listen-address=0.0.0.0:9100";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/node-exporter.out.log";
      StandardErrorPath = "/tmp/node-exporter.err.log";
    };
  };

  # Mount the shared home without taking ownership of SIP-protected Apple
  # files such as /etc/fstab or /etc/auto_master. The scheduled launchd job is
  # idempotent and naturally retries while networking or Trex is unavailable.
  launchd.daemons.hellas-home-mount = {
    command = "${pkgs.writeShellScript "mount-hellas-home" ''
      mount_point=/System/Volumes/Data/mnt/Home
      if ! /sbin/mount | /usr/bin/grep -Fq " on $mount_point ("; then
        /sbin/mount_nfs -o nfsvers=4.1,sec=sys,resvport,hard,intr ${trexIp}:/home "$mount_point"
      fi
    ''}";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 30;
      ProcessType = "Background";
      StandardOutPath = "/var/log/hellas-home-mount.log";
      StandardErrorPath = "/var/log/hellas-home-mount.error.log";
    };
  };

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

      # A synthetic empty directory cannot contain children, so expose a
      # writable Data-volume directory at /mnt instead. Synthetic entities are
      # applied during early boot; restitching the root live disrupts services.
      mkdir -p /System/Volumes/Data/mnt/Home
      mnt_synthetic=${lib.escapeShellArg mntSynthetic}
      if ! grep -Fqx "$mnt_synthetic" /etc/synthetic.conf; then
        echo "configuring synthetic /mnt root..."
        mnt_synthetic_tmp="$(mktemp /etc/synthetic.conf.XXXXXX)"
        awk '$1 != "mnt" { print }' /etc/synthetic.conf > "$mnt_synthetic_tmp"
        printf '%s\n' "$mnt_synthetic" >> "$mnt_synthetic_tmp"
        chown root:wheel "$mnt_synthetic_tmp"
        chmod 0644 "$mnt_synthetic_tmp"
        mv "$mnt_synthetic_tmp" /etc/synthetic.conf
      fi
    '';
  };

  # Used for backwards compatibility, please read the changelog before changing.
  system.stateVersion = 3;

  # NFS client configuration
  environment.etc."nfs.conf".text = ''
    nfs.client.mount.options = vers=4.1,sec=sys,resvport
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
