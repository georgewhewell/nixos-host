{pkgs, ...}: {
  home.packages = with pkgs;
    [
      xournalpp
      yt-dlp
      #      discord
      # code-cursor

      telegram-desktop
      signal-desktop
      element-desktop
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      vlc
      # calibre
      # signal
      spotify
      monero-gui
      tor-browser
      zoom-us
      cool-retro-term
      element-desktop

      # openshot-qt
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") [
      stats
    ];
}
