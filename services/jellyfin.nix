{pkgs, network, ...}: let
  domain = network.publicFqdn "jellyfin";
in {
  sconfig.gcp-ddns = {
    aRecords = [domain];
    aaaaRecords = [domain];
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8096";
      proxyWebsockets = true;
    };
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  systemd.services."jellyfin" = {
    bindsTo = ["mnt-Media.mount"];
    after = ["mnt-Media.mount"];
    serviceConfig.MemoryDenyWriteExecute = false;
  };

  users.users.jellyfin.extraGroups = ["video" "render"];

  # environment.systemPackages = with pkgs; [ffmpeg libva1 libva-utils];
}
