{network, ...}: let
  domain = network.publicFqdn "jellyfin";
  # Jellyfin moved into the arr-servers container (2026-08-09) so all the media
  # services share one sandbox. nginx still terminates TLS on trex and proxies
  # across to the container's own address, exactly as it already does for
  # radarr and sonarr in services/nginx.nix.
  #
  # Nothing else about the service is declared here any more: the unit, its
  # user, its state directory and its firewall live in
  # containers/arr-servers.nix. /var/lib/jellyfin stays on the host as the
  # bind-mount source and is still covered by trex's persistence list.
  #
  # The old `users.users.jellyfin.extraGroups = ["video" "render"]` is gone
  # deliberately: trex exposes only /dev/dri/card0 (the ASPEED BMC
  # framebuffer) and no renderD128, so there is no render node and jellyfin
  # has always transcoded on CPU here. There is nothing to pass through.
  arrIp = network.ipOf "lan" network.hosts."arr-servers".addresses.lan;
in {
  sconfig.gcp-ddns = {
    aRecords = [domain];
    aaaaRecords = [domain];
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://${arrIp}:8096";
      proxyWebsockets = true;
    };
  };
}
