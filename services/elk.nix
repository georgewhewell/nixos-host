{ config, lib, pkgs, ... }:

with lib; # commands such as mkOption, types are within lib.

let
    cfg = config.services.elk; # this is an alias to config.services.elk that is used in our implementation below

    fromUnit = unit: ''
        pipe {
            command => "${pkgs.systemd}/bin/journalctl -fu ${unit} -o json"
            tags => "${unit}"
            type => "syslog"
            codec => json {}
        }
    '';
in
{
   ###### interface

    options.services.elk = {
        enable = mkOption {
            description = "Whether to enable the ELK stack.";
            default = false;
            type = types.bool;
        };

        systemdUnits = mkOption {
            description = "The systemd units to send to our ELK stack.";
            default = [];
            type = types.listOf types.str;
        };

        listenAddress = mkOption {
            description = "The IP address or host to listen on Kibana.";
            default = "127.0.0.1";
            type = types.str;
        };

        additionalInputConfig = mkOption {
            description = "Additional logstash input configurations.";
            default = "";
            type = types.str;
        };
   };

   ##### implementation

   config = mkIf cfg.enable {

  security.acme.certs."elk.satanic.link" = {
     email = "georgerw@gmail.com";
     postRun = ''systemctl reload nginx.service'';
  };

  services.nginx.virtualHosts."elk.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:5601";
    };
  };

        services.logstash = {
            enable = true;
            plugins = [ pkgs.logstash-contrib ];
            inputConfig = (concatMapStrings fromUnit cfg.systemdUnits) + cfg.additionalInputConfig;
            filterConfig = ''
                if [type] == "syslog" {
                    # Keep only relevant systemd fields
                    # http://www.freedesktop.org/software/systemd/man/systemd.journal-fields.html
                    prune {
                        whitelist_names => [
                            "type", "@timestamp", "@version",
                            "MESSAGE", "PRIORITY", "SYSLOG_FACILITY", "_SYSTEMD_UNIT"
                        ]
                    }
                    mutate {
                        rename => { "_SYSTEMD_UNIT" => "unit" }
                    }
                }
            '';
            outputConfig = ''
                elasticsearch {
                    protocol => "http"
                    host => "127.0.0.1:9200"
                }
            '';
        };

        services.elasticsearch = {
            enable = true;
        };

        services.kibana = {
            enable = true;
            listenAddress = cfg.listenAddress;
        };
        
    };
}
