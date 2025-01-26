{pkgs, ...}: {
  home.packages = with pkgs;
    [
      tdesktop
      element-desktop
      signal-desktop

      xournalpp
      yt-dlp
      discord
    ]
    ++ lib.optionals (pkgs.system == "x86_64-linux") [
      vlc
      calibre
      spotify
      monero-gui
      tor-browser-bundle-bin
      zoom-us
      cool-retro-term
      openshot-qt
    ];
}
