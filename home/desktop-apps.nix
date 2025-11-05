{pkgs, ...}: {
  home.packages = with pkgs;
    [
      element-desktop
      xournalpp
      yt-dlp
      discord
      code-cursor
      spotify
      telegram-desktop
    ]
    ++ lib.optionals (pkgs.system == "x86_64-linux") [
      vlc
      calibre
      signal-desktop
      monero-gui
      tor-browser-bundle-bin
      zoom-us
      cool-retro-term
      openshot-qt
    ]
    ++ lib.optionals (pkgs.system == "aarch64-darwin") [
      stats
      signal-desktop-bin
    ];
}
