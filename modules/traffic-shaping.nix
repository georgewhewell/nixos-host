{ config, lib, pkgs, ... }:

with lib;
let
  script = pkgs.fetchurl {
    url = "https://gist.githubusercontent.com/eqhmcow/939373/raw/2608f60eaf777f0abb6729f986782a1fdab7f56a/hfsc-shape.sh";
    sha256 = "10qmggzly7sc7qdjnn1281q5rhfwgshm2xv4mp96lnmsyi2pd9sp";
    name = "hfsc-shape.sh";
  };
  cfg = config.networking.trafficShaping;
in
{
  options.networking.trafficShaping = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enables traffic shaping
      '';
    };

    wanInterface = mkOption {
      type = types.str;
      default = null;
      description = ''
        WAN
      '';
    };

    lanInterface = mkOption {
      type = types.str;
      default = null;
      description = ''
        LAN
      '';
    };

    lanNetwork = mkOption {
      type = types.str;
      default = null;
      description = ''
        LAN Network
      '';
    };

    maxDown = mkOption {
      type = types.str;
      default = null;
    };

    maxUp = mkOption {
      type = types.str;
      default = null;
    };

  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ bc ];
    boot.kernelModules = [ "msr" ];
    systemd.services.traffic-shaping =
      let
        customScript =
          pkgs.runCommand "hfsc-shape-custom.sh"
            { } ''
            substitute ${script} $out \
              --replace "/bin/bash" "${pkgs.bash}/bin/bash" \
              --replace "TC=/sbin/tc" "TC=${pkgs.iproute}/bin/tc" \
              --replace "WAN_INTERFACE=eth1" "WAN_INTERFACE=${cfg.wanInterface}" \
              --replace "LAN_INTERFACE=eth0" "LAN_INTERFACE=${cfg.lanInterface}" \
              --replace "LAN_NETWORK=192.168.1.0/24" "LAN_NETWORK=${cfg.lanNetwork}" \
              --replace "MAX_DOWNRATE=6144kbit" "MAX_DOWNRATE=${cfg.maxDown}" \
              --replace "MAX_UPRATE=384kbit" "MAX_UPRATE=${cfg.maxUp}"
          ''; in
      {
        wantedBy = [ "networking.service" ];
        serviceConfig.Type = "oneshot";
        script = "${pkgs.bash}/bin/bash ${customScript}";
      };
  };
  meta = { };
}
