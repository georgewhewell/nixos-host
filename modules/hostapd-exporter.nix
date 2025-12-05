{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hostapd-exporter;

  defaultMetricsConfig = {
    DEFAULT = {
      PORT = cfg.port;
      CTRL_IF_DIR = cfg.controlInterfaceDir;
    };
    METRICS_AP = [
      {
        name_hostapd = "num_sta[0]";
        name_prometheus = "num_stations";
        type = "gauge";
        help = "Number of active stations of the VAP";
      }
      {
        name_hostapd = "channel";
        name_prometheus = "channel";
        type = "gauge";
        help = "Primary channel of the VAP";
      }
      {
        name_hostapd = "freq";
        name_prometheus = "freq_Hz";
        type = "gauge";
        help = "Primary frequency of the VAP";
      }
      {
        name_hostapd = "max_txpower";
        name_prometheus = "max_txpower_dBm";
        type = "gauge";
        help = "Max TX Power of the VAP in dBms";
      }
      {
        name_hostapd = "ieee80211n";
        name_prometheus = "wifi_standard_n_enabled";
        type = "gauge";
        help = "WiFi 4 (802.11n) enabled";
      }
      {
        name_hostapd = "ieee80211ac";
        name_prometheus = "wifi_standard_ac_enabled";
        type = "gauge";
        help = "WiFi 5 (802.11ac) enabled";
      }
      {
        name_hostapd = "ieee80211ax";
        name_prometheus = "wifi_standard_ax_enabled";
        type = "gauge";
        help = "WiFi 6/6E (802.11ax) enabled";
      }
      {
        name_hostapd = "ieee80211be";
        name_prometheus = "wifi_standard_be_enabled";
        type = "gauge";
        help = "WiFi 7 (802.11be) enabled";
      }
      {
        name_hostapd = "vht_oper_chwidth";
        name_prometheus = "vht_channel_width";
        type = "gauge";
        help = "VHT channel width code";
      }
      {
        name_hostapd = "he_oper_chwidth";
        name_prometheus = "he_channel_width";
        type = "gauge";
        help = "HE channel width code";
      }
      {
        name_hostapd = "eht_oper_chwidth";
        name_prometheus = "eht_channel_width";
        type = "gauge";
        help = "EHT channel width code";
      }
      {
        name_hostapd = "secondary_channel";
        name_prometheus = "ht40_direction";
        type = "gauge";
        help = "HT40 secondary channel offset";
      }
      {
        name_hostapd = "vht_oper_centr_freq_seg0_idx";
        name_prometheus = "vht_center_freq_idx";
        type = "gauge";
        help = "VHT center frequency channel index";
      }
      {
        name_hostapd = "he_oper_centr_freq_seg0_idx";
        name_prometheus = "he_center_freq_idx";
        type = "gauge";
        help = "HE center frequency channel index";
      }
      {
        name_hostapd = "eht_oper_centr_freq_seg0_idx";
        name_prometheus = "eht_center_freq_idx";
        type = "gauge";
        help = "EHT center frequency channel index";
      }
    ];
    METRICS_STA = [
      {
        name_hostapd = "signal";
        name_prometheus = "signal_dBm";
        type = "gauge";
        help = "signal in dbms of a station in a VAP";
      }
      {
        name_hostapd = "rx_bytes";
        name_prometheus = "rx_bytes_total";
        type = "counter";
        help = "Received bytes from the STA to the VAP";
      }
      {
        name_hostapd = "tx_bytes";
        name_prometheus = "tx_bytes_total";
        type = "counter";
        help = "Transmitted bytes from the VAP to the STA";
      }
      {
        name_hostapd = "connected_time";
        name_prometheus = "connected_time_total";
        type = "counter";
        help = "Connected time in seconds of a STA in a VAP";
      }
      {
        name_hostapd = "rx_rate_info";
        name_prometheus = "rx_rate_bps";
        type = "gauge";
        help = "Link rate from the STA to the VAP in bps";
      }
      {
        name_hostapd = "tx_rate_info";
        name_prometheus = "tx_rate_bps";
        type = "gauge";
        help = "Link rate from the VAP to the STA in bps";
      }
      {
        name_hostapd = "total_airtime";
        name_prometheus = "total_airtime";
        type = "gauge";
        help = "Total airtime consumed by a STA";
      }
      {
        name_hostapd = "backlog_bytes";
        name_prometheus = "backlog_bytes_total";
        type = "counter";
        help = "Backlogged packets";
      }
      {
        name_hostapd = "last_ack_signal";
        name_prometheus = "last_ack_signal_dBm";
        type = "gauge";
        help = "Last ACK signal strength";
      }
      {
        name_hostapd = "rx_packets";
        name_prometheus = "rx_packets_total";
        type = "counter";
        help = "Total received packets";
      }
      {
        name_hostapd = "tx_packets";
        name_prometheus = "tx_packets_total";
        type = "counter";
        help = "Total transmitted packets";
      }
      {
        name_hostapd = "inactive_msec";
        name_prometheus = "inactive_milliseconds";
        type = "gauge";
        help = "Client inactivity time";
      }
    ];
  };

  configFile = pkgs.writeText "hostapd-exporter-config.json" (builtins.toJSON defaultMetricsConfig);
in {
  options.services.hostapd-exporter = {
    enable = lib.mkEnableOption "hostapd Prometheus exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9551;
      description = "Port to expose metrics on";
    };

    controlInterfaceDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/hostapd";
      description = "Directory containing hostapd control interface sockets";
    };

    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["wlan0" "wlan1"];
      description = "List of wireless interfaces to monitor";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for metrics endpoint";
    };
  };

  config = lib.mkIf cfg.enable {
    # Systemd template to create symlinks for hostapd sockets
    # The exporter expects sockets named hostapd_<interface>
    systemd.services."hostapd-symlink@" = {
      description = "Create hostapd socket symlink for %i";
      after = ["hostapd.service"];
      requires = ["hostapd.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/ln -sf ${cfg.controlInterfaceDir}/%i ${cfg.controlInterfaceDir}/hostapd_%i";
        ExecStop = "${pkgs.coreutils}/bin/rm -f ${cfg.controlInterfaceDir}/hostapd_%i";
      };
    };

    # Main exporter service
    systemd.services.hostapd-exporter = {
      description = "hostapd Prometheus Exporter";
      after = ["hostapd.service"] ++ (map (iface: "hostapd-symlink@${iface}.service") cfg.interfaces);
      requires = ["hostapd.service"] ++ (map (iface: "hostapd-symlink@${iface}.service") cfg.interfaces);
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = "${pkgs.hostapd-exporter}/bin/hostapd-exporter ${configFile}";
        User = "hostapd-exporter";
        Group = "hostapd-exporter";
        SupplementaryGroups = ["wheel"];
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    users.users.hostapd-exporter = {
      isSystemUser = true;
      group = "hostapd-exporter";
      description = "hostapd Prometheus Exporter user";
    };

    users.groups.hostapd-exporter = {};

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
