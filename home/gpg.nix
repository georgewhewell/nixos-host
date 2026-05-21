{
  pkgs,
  lib,
  config,
  network,
  ...
}: {
  programs.gpg = {
    enable = true;
    settings = {
      trust-model = "always";
      ignore-time-conflict = true;
      ignore-valid-from = true;
      ignore-crc-error = true;
      allow-weak-digest-algos = true;
    };
  };

  # Your public key for automatic import on remote systems (renewed 2025-09-02, expires 2027-09-01)
  home.file.".gnupg/grw-public-key.asc".text = ''
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    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
    lLSrThDT/W+T/9Gy92wK0suj3bhRf4zOyXA=
    =TzIb
    -----END PGP PUBLIC KEY BLOCK-----
  '';

  # Automatically import your public key and set trust on activation
  home.activation.gpgSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Import your public key if not already present
    if ! $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpg --list-keys 0C414B6F2BA7BB19 >/dev/null 2>&1; then
      $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpg --import ${config.home.homeDirectory}/.gnupg/grw-public-key.asc 2>/dev/null || true
    fi

    # Set ultimate trust for your key
    echo "4ED64FA5BBF73612035B86B20C414B6F2BA7BB19:6:" | $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpg --import-ownertrust 2>/dev/null || true
  '';

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    sshKeys = ["EEB6A2D42BF04599AFEF0E9C104AB9B2E16AE31D"];
    # Don't set pinentry here, we'll use a dynamic script
    pinentry.package = null;
    # Cache PIN for longer to avoid repeated prompts
    defaultCacheTtl = 28800; # 8 hours
    defaultCacheTtlSsh = 28800; # 8 hours
    maxCacheTtl = 86400; # 24 hours
    maxCacheTtlSsh = 86400; # 24 hours
    extraConfig = let
      # gpg.nix is only loaded for graphical homes (see modules/home-manager.nix),
      # so we hard-code a GUI pinentry here. pinentry-qt is the only Linux
      # pinentry that works under both Wayland and X11; pinentry-mac on Darwin.
      # When there's no display (SSH'd into the desktop), fall back to TTY.
      pinentrySelect =
        if pkgs.stdenv.isDarwin
        then "${pkgs.pinentry_mac}/bin/pinentry-mac"
        else pkgs.writeShellScript "pinentry-graphical" ''
          if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; then
            exec ${pkgs.pinentry-qt}/bin/pinentry-qt "$@"
          fi
          exec ${pkgs.pinentry-tty}/bin/pinentry-tty "$@"
        '';
    in ''
      pinentry-program ${pinentrySelect}
    '';
  };

  # GPG agent forwarding only to LAN machines (they have /run/user/1000/gnupg/)
  programs.ssh.matchBlocks = {
    "*.${network.domains.lan}" = {
      extraOptions = {
        StreamLocalBindUnlink = "yes";
      };
      remoteForwards = [
        {
          bind.address = "/run/user/1000/gnupg/S.gpg-agent";
          host.address =
            if pkgs.stdenv.isDarwin
            then "/Users/grw/.gnupg/S.gpg-agent.extra"
            else "/run/user/1000/gnupg/S.gpg-agent.extra";
        }
        {
          bind.address = "/run/user/1000/gnupg/S.gpg-agent.ssh";
          host.address =
            if pkgs.stdenv.isDarwin
            then "/Users/grw/.gnupg/S.gpg-agent.ssh"
            else "/run/user/1000/gnupg/S.gpg-agent.ssh";
        }
      ];
    };
  };

  programs.zsh.initContent = lib.mkAfter ''
    export GPG_TTY=$(tty)

    ${
      if pkgs.stdenv.isLinux
      then ''
        # On Linux, use forwarded GPG agent socket if available AND we're in SSH session
        if [[ -n "$SSH_CONNECTION" ]] && [[ -S "/run/user/1000/gnupg/S.gpg-agent.ssh" ]]; then
          export SSH_AUTH_SOCK="/run/user/1000/gnupg/S.gpg-agent.ssh"
        fi
      ''
      else ""
    }
  '';

  # libsecret backend for Zed et al — pass-secret-service exposes the
  # standard org.freedesktop.secrets D-Bus API and stores everything in
  # the pass store, encrypted with the user's GPG key (YubiKey-backed).
  # The package ships its own dbus-org.freedesktop.secrets.service unit,
  # auto-activated by D-Bus on first request. We override it here only
  # to inject PASSWORD_STORE_DIR (XDG location) and PATH (gpg/pass).
  home.packages = with pkgs; [
    (
      if pkgs.stdenv.isDarwin
      then pinentry_mac
      else pinentry-qt
    )
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    pkgs.pass-secret-service
  ];

  systemd.user.services."dbus-org.freedesktop.secrets" = lib.mkIf pkgs.stdenv.isLinux {
    Unit.Description = "Expose libsecret D-Bus API with pass as backend";
    Service = {
      BusName = "org.freedesktop.secrets";
      # --path is required: pypass hardcodes ~/.password-store and
      # ignores $PASSWORD_STORE_DIR. We use the XDG location to match
      # programs.password-store in home/development.nix.
      ExecStart = "${pkgs.pass-secret-service}/bin/pass_secret_service --path %h/.local/share/password-store";
      Environment = [
        "PATH=${lib.makeBinPath [pkgs.pass pkgs.gnupg]}"
      ];
      Restart = "on-failure";
    };
  };

  services.keybase.enable = pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64;
  services.kbfs.enable = pkgs.stdenv.isLinux && pkgs.stdenv.isx86_64;
}
