{pkgs, lib, ...}: {
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
      pinentryAuto = pkgs.writeShellScript "pinentry-auto" ''
        # Smart pinentry selector based on context
        
        # Allow explicit control via environment variable
        case "$PINENTRY_USER_DATA" in
          *USE_TTY*) exec ${pkgs.pinentry-tty}/bin/pinentry-tty "$@" ;;
          *USE_CURSES*) exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@" ;;
          ${if pkgs.stdenv.isDarwin then ''
          *USE_MAC*) exec ${pkgs.pinentry_mac}/bin/pinentry-mac "$@" ;;
          '' else ""}
        esac
        
        # Auto-detect based on environment
        ${if pkgs.stdenv.isDarwin then ''
          # On Darwin, prefer GUI unless we're in pure SSH
          if [ -n "$DISPLAY" ] || [ -z "$SSH_TTY" ]; then
            exec ${pkgs.pinentry_mac}/bin/pinentry-mac "$@"
          else
            exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
          fi
        '' else ''
          # On Linux, use curses for SSH, GUI otherwise
          if [ -n "$DISPLAY" ] && [ -z "$SSH_TTY" ]; then
            # Try GUI pinentries if available
            for p in ${pkgs.pinentry-gtk2}/bin/pinentry-gtk-2 ${pkgs.pinentry-qt}/bin/pinentry-qt; do
              [ -x "$p" ] && exec "$p" "$@"
            done
          fi
          exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
        ''}
      '';
    in ''
      pinentry-program ${pinentryAuto}
    '';
  };

  programs.ssh = {
    extraConfig = ''
      # Update GPG TTY when initiating SSH connections
      Match host * exec "gpg-connect-agent --no-autostart UPDATESTARTUPTTY /bye >/dev/null 2>&1"
      
    '' + (
      if pkgs.stdenv.isDarwin then ''
        Host *.satanic.link 78.47.106.113
          RemoteForward /run/user/1000/gnupg/S.gpg-agent ~/.gnupg/S.gpg-agent.extra
          RemoteForward /run/user/1000/gnupg/S.gpg-agent.ssh ~/.gnupg/S.gpg-agent.ssh
          StreamLocalBindUnlink yes
      '' else ''
        Host *.satanic.link 78.47.106.113
          RemoteForward /run/user/1000/gnupg/S.gpg-agent /run/user/1000/gnupg/S.gpg-agent.extra
          RemoteForward /run/user/1000/gnupg/S.gpg-agent.ssh /run/user/1000/gnupg/S.gpg-agent.ssh
          StreamLocalBindUnlink yes
      ''
    );
  };
  
  programs.zsh.initContent = lib.mkAfter ''
    export GPG_TTY=$(tty)
    
    ${if pkgs.stdenv.isLinux then ''
      # On Linux, use forwarded GPG agent socket if available AND we're in SSH session
      if [[ -n "$SSH_CONNECTION" ]] && [[ -S "/run/user/1000/gnupg/S.gpg-agent.ssh" ]]; then
        export SSH_AUTH_SOCK="/run/user/1000/gnupg/S.gpg-agent.ssh"
      fi
    '' else ""}
    
    # Don't update TTY here - it's now handled by SSH Match rule
  '';

  home.packages = with pkgs; [
    (if pkgs.stdenv.isDarwin then pinentry_mac else pinentry-curses)
  ];
}
