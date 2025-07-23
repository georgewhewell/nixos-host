{pkgs, ...}: {
  home.packages = with pkgs; [
    (writeShellScriptBin "kill-pinentry" ''
      # Kill any stuck pinentry processes
      pkill -f pinentry || true
      echo "Killed any stuck pinentry processes"
      
      # Also restart gpg-agent if needed
      if [[ "$1" == "--restart" ]]; then
        gpgconf --kill gpg-agent
        gpgconf --launch gpg-agent
        echo "Restarted GPG agent"
      fi
    '')
  ];
}