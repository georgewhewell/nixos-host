{pkgs, ...}: {
  home.packages = with pkgs;
    [
      element-desktop
      xournalpp
      yt-dlp
      discord
      code-cursor
      # spotify
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
      tdesktop
    ]
    ++ lib.optionals (pkgs.system == "aarch64-darwin") [
      # lmstudio
      stats
      signal-desktop-bin
      # whatsapp-for-mac
    ];
}
