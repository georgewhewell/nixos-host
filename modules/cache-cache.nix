{ config, lib, ... }:

with lib;
let
  cfg = config.services.nixBinaryCacheCache;

  nginxCfg = config.services.nginx;

  cacheFallbackConfig = {
    proxyPass = "$upstream_endpoint";
    extraConfig = ''
      # Default is HTTP/1, keepalive is only enabled in HTTP/1.1.
      proxy_http_version 1.1;

      # Remove the Connection header if the client sends it, it could
      # be "close" to close a keepalive connection
      proxy_set_header Connection "";

      # Needed for CloudFront.
      proxy_ssl_server_name on;
      proxy_set_header Host $proxy_host;
      proxy_cache nix_cache_cache;
      proxy_cache_valid 200 302 60m;
      proxy_cache_valid 404 1m;

      expires max;
      add_header Cache-Control $nix_cache_cache_header always;
    '';
  };

in
{
  options = {
    services.nixBinaryCacheCache = {
      enable = mkEnableOption "Nix binary cache cache";

      virtualHost = mkOption {
        type = types.str;
        default = "nix-cache";
        description = ''
          Name of the nginx virtualhost to use and setup. If null, do
          not setup any virtualhost.
        '';
      };

      resolver = mkOption {
        type = types.str;
        default = "1.1.1.1";
        description = "Address of DNS resolver.";
      };

      cacheDir = mkOption {
        type = types.str;
        default = "/var/cache/nix-cache-cache";
        description = ''
          Where nginx should store cached data.
        '';
      };

      maxSize = mkOption {
        type = types.str;
        default = "10g";
        description = "Maximum cache size.";
      };
    };
  };

  config = mkIf cfg.enable {

    systemd.services.nginx.serviceConfig.ReadWritePaths = [ cfg.cacheDir "/srv/www/nix-cache-cache" ];

    services.nginx = {
      enable = true;
      appendHttpConfig = ''
        proxy_cache_path ${cfg.cacheDir}
          levels=1:2
          keys_zone=nix_cache_cache:100m
          max_size=${cfg.maxSize}
          inactive=365d;

        # Cache only success status codes; in particular we don't want
        # to cache 404s. See https://serverfault.com/a/690258/128321.
        map $status $nix_cache_cache_header {
          200     "public";
          302     "public";
          default "no-cache";
        }
      '';

      virtualHosts.${cfg.virtualHost} = {
        forceSSL = true;
        enableACME = true;
        extraConfig = ''
          resolver ${cfg.resolver} valid=10s ipv6=off;
          set $upstream_endpoint http://cache.nixos.org;
        '';
        locations."/" =
          {
            root = "/srv/www/nix-cache-cache";
            extraConfig = ''
              expires max;
              add_header Cache-Control $nix_cache_cache_header always;

              # Ask the upstream server if a file isn't available
              # locally.
              error_page 404 = @fallback;

              # Don't bother logging the above 404.
              log_not_found off;
            '';
          };

        locations."@fallback" = cacheFallbackConfig;

        # We always want to copy cache.nixos.org's nix-cache-info
        # file, and ignore our own, because `nix-push` by default
        # generates one without `Priority` field, and thus that file
        # by default has priority 50 (compared to cache.nixos.org's
        # `Priority: 40`), which will make download clients prefer
        # `cache.nixos.org` over our binary cache.
        locations."~ ^/nix-cache-info" = cacheFallbackConfig;
      };
    };
  };
}
