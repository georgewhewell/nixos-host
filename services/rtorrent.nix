{
  config,
  pkgs,
  ...
}: let
  peer-port = 51412;
  web-port = 8112;
in {
  services.rtorrent = {
    enable = true;
    port = peer-port;
    # package = pkgs.jesec-rtorrent; # currently (2024-12-30) rtorrent 0.15.0 in nixpkgs unstable is incompatible with flood, this is why a fork is used
    openFirewall = true;
  };

  services.flood = {
    enable = true;
    host = "192.168.23.8";
    port = web-port;
    openFirewall = true;
    extraArgs = ["--rtsocket=${config.services.rtorrent.rpcSocket}"];
  };
  # allow access to the socket by putting it in the same group as rtorrent service
  # the socket will have g+w permissions
  systemd.services.flood.serviceConfig.SupplementaryGroups = [config.services.rtorrent.group];
}
