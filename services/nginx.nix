{...}: {
  networking.firewall.allowedTCPPorts = [80 443];

  # Configure mtail for nginx log parsing
  services.mtail = {
    enable = true;
    port = 3903;
    logs = ["/var/log/nginx/access.log"];
    extraGroups = ["nginx"];
    debug = true;  # Enable debug logging to troubleshoot

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
    domains = [
      "home.satanic.link"
      "radarr.satanic.link"
      "sonarr.satanic.link"
      "autobrr.satanic.link"
      "static.satanic.link"
    ];
  in {
    aRecords = domains;
    aaaaRecords = domains;
  };

  services.nginx.virtualHosts."home.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = ''
      proxy_buffering off;
    '';
    locations."/" = {
      proxyPass = "http://192.168.23.1:8123";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."radarr.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
      '';
      proxyPass = "http://192.168.23.15:7878";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."sonarr.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
      '';
      proxyPass = "http://192.168.23.15:8989";
      proxyWebsockets = true;
    };
  };

  services.nginx.virtualHosts."autobrr.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      extraConfig = ''
        proxy_buffering off;
      '';
      proxyPass = "http://192.168.23.15:7474";
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

  services.nginx.virtualHosts."static.satanic.link" = {
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