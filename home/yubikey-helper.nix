{pkgs, ...}: {
  home.packages = with pkgs; [
    (writeShellScriptBin "yubikey-unlock" ''
      #!/usr/bin/env bash
      set -e
      
      echo "🔐 Pre-unlocking Yubikey for SSH and GPG..."
      
      # Test SSH key (this will trigger pinentry if needed)
      if ! ssh-add -L >/dev/null 2>&1; then
        echo "❌ Failed to list SSH keys. Is your Yubikey inserted?"
        exit 1
      fi
      
      echo "✅ SSH key available"
      
      # Test GPG signing (this will trigger pinentry if needed)
      if ! echo "test" | gpg --clearsign >/dev/null 2>&1; then
        echo "❌ Failed to sign with GPG. Is your Yubikey inserted?"
        exit 1
      fi
      
      echo "✅ GPG signing works"
      echo ""
      echo "🎉 Yubikey unlocked! PIN cache will last 8 hours."
      echo "You can now SSH to remote machines with GPG forwarding."
    '')
    
    (writeShellScriptBin "pinentry-force" ''
      #!/usr/bin/env bash
      # Force a specific pinentry type for the current command
      # Usage: pinentry-force curses gpg --sign
      #        pinentry-force mac ssh-add -L
      
      if [ $# -lt 2 ]; then
        echo "Usage: pinentry-force <type> <command...>"
        echo "Types: tty, curses, mac"
        exit 1
      fi
      
      TYPE=$1
      shift
      
      case "$TYPE" in
        tty|curses|mac)
          export PINENTRY_USER_DATA="USE_''${TYPE^^}"
          ;;
        *)
          echo "Unknown pinentry type: $TYPE"
          echo "Valid types: tty, curses, mac"
          exit 1
          ;;
      esac
      
      exec "$@"
    '')
  ];
}