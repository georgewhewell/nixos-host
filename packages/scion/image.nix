{
  lib,
  dockerTools,
  buildEnv,
  writeText,
  bashInteractive,
  zsh,
  coreutils,
  findutils,
  gnused,
  gnugrep,
  gawk,
  diffutils,
  gnutar,
  gzip,
  which,
  less,
  jq,
  ripgrep,
  curl,
  wget,
  git,
  tmux,
  shadow,
  sudo,
  cacert,
  iana-etc,
  tzdata,
  python3,
  nodejs_20,
  claude-code,
  antigravity,
  codex,
  nix,
  direnv,
  nix-direnv,
  scion,
}: let
  passwd = writeText "passwd" ''
    root:x:0:0:root:/root:${bashInteractive}/bin/bash
    scion:x:1000:1000:scion:/home/scion:${zsh}/bin/zsh
    nobody:x:65534:65534:Nobody:/var/empty:/bin/false
  '';

  group = writeText "group" ''
    root:x:0:
    wheel:x:1:scion
    scion:x:1000:
    nobody:x:65534:
  '';

  shadowFile = writeText "shadow" ''
    root:!x:::::::
    scion:!x:::::::
    nobody:!x:::::::
  '';

  sudoers = writeText "sudoers-scion" ''
    Defaults env_keep += "PATH NIX_PATH NIX_REMOTE NIX_CONFIG NIX_USER_CONF_FILES"
    root ALL=(ALL) ALL
    %wheel ALL=(ALL) NOPASSWD: ALL
    scion ALL=(ALL) NOPASSWD: ALL
  '';

  nsswitch = writeText "nsswitch.conf" ''
    passwd:    files
    group:     files
    shadow:    files
    hosts:     files dns
    networks:  files dns
    services:  files
    protocols: files
    rpc:       files
  '';

  nixConf = writeText "nix.conf" ''
    experimental-features = nix-command flakes
    sandbox = false
    accept-flake-config = true
    build-users-group =
    extra-trusted-users = root scion
  '';

  rootEnv = buildEnv {
    name = "scion-agents-rootfs";
    paths = [
      scion
      claude-code
      antigravity
      codex
      nodejs_20
      python3
      nix
      direnv
      nix-direnv
      bashInteractive
      zsh
      coreutils
      findutils
      gnused
      gnugrep
      gawk
      diffutils
      gnutar
      gzip
      which
      less
      jq
      ripgrep
      curl
      wget
      git
      tmux
      shadow
      sudo
      cacert
      iana-etc
      tzdata
    ];
    pathsToLink = ["/bin" "/share" "/lib"];
  };
in
  dockerTools.buildLayeredImage {
    name = "scion-agents";
    tag = "latest";

    contents = [rootEnv];

    enableFakechroot = true;
    fakeRootCommands = ''
      mkdir -p \
        /workspace \
        /home/scion/.scion \
        /home/scion/.claude \
        /home/scion/.gemini \
        /home/scion/.codex \
        /home/scion/.config \
        /commandhistory \
        /opt/scion/bin \
        /etc/sudoers.d \
        /etc/ssl/certs \
        /etc/nix \
        /tmp \
        /root \
        /var/empty \
        /usr/bin \
        /nix/store \
        /nix/var/nix

      install -m 0644 ${passwd}     /etc/passwd
      install -m 0644 ${group}      /etc/group
      install -m 0640 ${shadowFile} /etc/shadow
      install -m 0644 ${nsswitch}   /etc/nsswitch.conf
      install -m 0440 ${sudoers}    /etc/sudoers.d/scion
      install -m 0644 ${nixConf}    /etc/nix/nix.conf
      cat > /etc/sudoers <<'EOF'
      #includedir /etc/sudoers.d
      EOF
      chmod 0440 /etc/sudoers

      ln -s ${cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
      ln -s ${cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
      ln -s ${iana-etc}/etc/protocols /etc/protocols
      ln -s ${iana-etc}/etc/services  /etc/services
      ln -s ${tzdata}/share/zoneinfo  /etc/zoneinfo
      ln -s /bin/env /usr/bin/env
      ln -sf ${bashInteractive}/bin/bash /bin/sh

      # Pre-seed scion's ~/.config/nix so flake commands work without --extra-experimental-features
      mkdir -p /home/scion/.config/nix
      install -m 0644 ${nixConf} /home/scion/.config/nix/nix.conf

      # Wire nix-direnv hook for scion users that opt in
      cat > /home/scion/.direnvrc <<'EOF'
      source ${nix-direnv}/share/nix-direnv/direnvrc
      EOF

      touch /commandhistory/.bash_history
      chmod 1777 /tmp
      chown -R 1000:1000 /home/scion /workspace /commandhistory /opt/scion
    '';

    config = {
      Entrypoint = ["${scion}/bin/sciontool" "init" "--"];
      Cmd = ["${bashInteractive}/bin/bash"];
      WorkingDir = "/workspace";
      User = "0:0";
      Env = [
        "PATH=/opt/scion/bin:/bin:/sbin:/usr/bin:/usr/sbin"
        "SHELL=${zsh}/bin/zsh"
        "EDITOR=nano"
        "VISUAL=nano"
        "DEVCONTAINER=true"
        "LC_ALL=C.UTF-8"
        "LANG=C.UTF-8"
        "TZ=UTC"
        "ANTHROPIC_MODEL=opus"
        "ANTHROPIC_SMALL_FAST_MODEL=haiku"
        "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
        "GIT_SSL_CAINFO=/etc/ssl/certs/ca-bundle.crt"
        # Talk to the host's nix-daemon when /nix/var/nix is bind-mounted.
        "NIX_REMOTE=daemon"
      ];
      Labels = {
        "org.opencontainers.image.title" = "scion-agents";
        "org.opencontainers.image.description" = "Nix-built Scion harness image — Claude/Gemini/Codex CLIs + nix client tools";
        "org.opencontainers.image.source" = "https://github.com/GoogleCloudPlatform/scion";
      };
    };
  }
