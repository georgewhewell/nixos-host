{network, pkgs, config, mkSecret, ...}: let
  routerHa = "${network.routerIp}:8123";
  arrIp = network.primaryIp network.hosts."arr-servers";
  trexIp = network.primaryIp network.hosts.trex;
  # Restrict a vhost to LAN + wireguard clients; everyone else gets 403.
  # The vhost still serves valid TLS internally; these names have no public DNS.
  lanOnly = ''
    allow ${network.vlans.lan.prefix}.0/${toString network.vlans.lan.cidr};
    allow ${network.vlans.wireguard.prefix}.0/${toString network.vlans.wireguard.cidr};
    deny all;
  '';

  # Internal-only services: no public A/AAAA records, so HTTP-01 can't renew.
  # Their certs use DNS-01 against Cloud DNS via lego's gcloud provider, reusing
  # the GCP ADC (authorized_user) stored in sops as acme-gcp-adc.
  internalCerts = ["radarr" "sonarr" "autobrr" "open-webui" "cache"];
  gcpAcmeEnv = pkgs.writeText "acme-gcloud.env" ''
    GCE_PROJECT=domain-owner
    GOOGLE_APPLICATION_CREDENTIALS=${config.sops.secrets.acme-gcp-adc.path}
  '';
in {
  networking.firewall.allowedTCPPorts = [80 443];

  # GCP ADC for lego DNS-01 (radarr/sonarr/autobrr internal certs).
  sops.secrets.acme-gcp-adc = mkSecret "acme-gcp-adc" {};

  # Configure mtail for nginx log parsing
  services.mtail = {
    enable = true;
    port = 3903;
    logs = ["/var/log/nginx/access.log"];
    extraGroups = ["nginx"];
    programs = {
      nginx = ''
        # Nginx access log parser for mtail
        # Parses combined log format with vhost and extracts metrics per domain

        counter nginx_http_requests_total by vhost, method, status, content_type
        counter nginx_http_response_size_bytes_total by vhost
        histogram nginx_http_request_duration_seconds by vhost, method, status buckets 0.001, 0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0

        # Combined log format with virtual host and request time
        # $host $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" $request_time
        /^(?P<vhost>[a-zA-Z0-9\.\-]+) (?P<remote_addr>[0-9A-Fa-f\.:]+) - (?P<remote_user>[^\s]+) \[(?P<time_local>[^\]]+)\] "(?P<method>[A-Z]+) (?P<uri>[^\s]+) (?P<protocol>[^\s"]+)" (?P<status>\d{3}) (?P<body_bytes_sent>\d+|-) "(?P<http_referer>[^"]*)" "(?P<http_user_agent>[^"]*)"(?: (?P<request_time>[\d\.]+))?/ {

          # Count requests by vhost, method, and status
          nginx_http_requests_total[$vhost][$method][$status][""]++

          # Track response sizes
          $body_bytes_sent != "-" {
            nginx_http_response_size_bytes_total[$vhost] += int($body_bytes_sent)
          }

          # Track request duration if available
          $request_time != "" {
            nginx_http_request_duration_seconds[$vhost][$method][$status] = float($request_time)
          }

          # Detect content type from URI extension
          $uri =~ /\.js$/ {
            nginx_http_requests_total[$vhost][$method][$status]["javascript"]++
          }
          $uri =~ /\.css$/ {
            nginx_http_requests_total[$vhost][$method][$status]["css"]++
          }
          $uri =~ /\.(jpg|jpeg|png|gif|webp|svg|ico)$/ {
            nginx_http_requests_total[$vhost][$method][$status]["image"]++
          }
          $uri =~ /\.(html|htm)$/ {
            nginx_http_requests_total[$vhost][$method][$status]["html"]++
          }
          $uri =~ /\.json$/ {
            nginx_http_requests_total[$vhost][$method][$status]["json"]++
          }
        }

        # Alternative format without request time
        /^(?P<vhost>[a-zA-Z0-9\.\-]+) (?P<remote_addr>[0-9A-Fa-f\.:]+) - (?P<remote_user>[^\s]+) \[(?P<time_local>[^\]]+)\] "(?P<method>[A-Z]+) (?P<uri>[^\s]+) (?P<protocol>[^\s"]+)" (?P<status>\d{3}) (?P<body_bytes_sent>\d+|-)/ {

          nginx_http_requests_total[$vhost][$method][$status][""]++

          $body_bytes_sent != "-" {
            nginx_http_response_size_bytes_total[$vhost] += int($body_bytes_sent)
          }
        }
      '';
    };
  };

  # Configure nginx to use custom log format with vhost and timing
  services.nginx.commonHttpConfig = ''
    log_format mtail '$host $remote_addr - $remote_user [$time_local] '
                     '"$request" $status $body_bytes_sent '
                     '"$http_referer" "$http_user_agent" $request_time';

    access_log /var/log/nginx/access.log mtail;
  '';

  # Create directory for static file hosting
  systemd.tmpfiles.rules = [
    "d /var/www/static 0755 nginx nginx -"
    "d /var/log/nginx 0755 nginx nginx -"
  ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "georgerw@gmail.com";

    # DNS-01 certs for the internal-only vhosts (no public DNS for HTTP-01).
    # group = nginx so the webserver can read the issued cert/key.
    certs = builtins.listToAttrs (map (name: {
      name = network.publicFqdn name;
      value = {
        dnsProvider = "gcloud";
        environmentFile = gcpAcmeEnv;
        group = "nginx";
      };
    }) internalCerts);
  };

  services.nginx = {
    enable = true;
    statusPage = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
  };

  sconfig.gcp-ddns = let
    # radarr/sonarr/autobrr are intentionally omitted: they are internal-only
    # (LAN + wireguard) and resolve via dnsmasq to trex. No public A/AAAA records
    # are published, and their certs renew via DNS-01 (see security.acme below).
    domains = map network.publicFqdn [
      "home"
      "static"
    ];
  in {
    aRecords = domains;
    aaaaRecords = domains;
  };

  services.nginx.virtualHosts.${network.publicFqdn "home"} = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      proxy_buffering off;
    '';
    # Fake DCR endpoint for Claude Code MCP compatibility
    locations."= /oauth/register" = {
      extraConfig = ''
        default_type application/json;
        return 201 '{"client_id":"http://127.0.0.1/oauth/client","client_secret":"","client_id_issued_at":0,"client_secret_expires_at":0,"redirect_uris":["http://127.0.0.1/callback","http://localhost/callback"]}';
      '';
    };
    # Intercept OAuth metadata to add registration_endpoint
    locations."= /.well-known/oauth-authorization-server" = let
      base = "https://${network.publicFqdn "home"}";
    in {
      extraConfig = ''
        default_type application/json;
        return 200 '{"authorization_endpoint":"${base}/auth/authorize","token_endpoint":"${base}/auth/token","revocation_endpoint":"${base}/auth/revoke","registration_endpoint":"${base}/oauth/register","response_types_supported":["code"],"service_documentation":"https://developers.home-assistant.io/docs/auth_api","issuer":"${base}"}';
      '';
    };
    locations."/" = {
      proxyPass = "http://${routerHa}";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts.${network.publicFqdn "radarr"} = {
    forceSSL = true;
    useACMEHost = network.publicFqdn "radarr";
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
        ${lanOnly}
      '';
      proxyPass = "http://${arrIp}:7878";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts.${network.publicFqdn "sonarr"} = {
    forceSSL = true;
    useACMEHost = network.publicFqdn "sonarr";
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
        ${lanOnly}
      '';
      proxyPass = "http://${arrIp}:8989";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts.${network.publicFqdn "autobrr"} = {
    forceSSL = true;
    useACMEHost = network.publicFqdn "autobrr";
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
        ${lanOnly}
      '';
      proxyPass = "http://${arrIp}:7474";
      proxyWebsockets = true;
    };
  };

  # Binary cache: nix-serve on trex signs with the trex.satanic.link key that
  # modules/nix.nix already trusts fleet-wide. NARs are large and immutable,
  # so skip proxy buffering and let clients stream.
  services.nginx.virtualHosts.${network.publicFqdn "cache"} = {
    forceSSL = true;
    useACMEHost = network.publicFqdn "cache";
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
        ${lanOnly}
      '';
      proxyPass = "http://${trexIp}:${toString config.services.nix-serve.port}";
    };
  };

  services.nginx.virtualHosts.${network.publicFqdn "open-webui"} = {
    forceSSL = true;
    useACMEHost = network.publicFqdn "open-webui";
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
        ${lanOnly}
      '';
      proxyPass = "http://${trexIp}:11111";
      proxyWebsockets = true;
    };
  };

  services.prometheus.exporters = {
    nginx = {
      enable = true;
      openFirewall = false;
    };
  };

  users.users.nginx = {
    extraGroups = ["acme"];
  };

  services.nginx.virtualHosts.${network.publicFqdn "static"} = {
    forceSSL = true;
    enableACME = true;
    root = "/var/www/static";
    locations."/" = {
      extraConfig = ''
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
      '';
    };
  };
}
