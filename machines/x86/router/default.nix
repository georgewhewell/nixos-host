{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: {
  /*
  router: cwwk 8845hs board
  */
  sconfig = {
    profile = "server";
    home-manager = {
      enable = true;
      enableVscodeServer = false;
    };
  };

  deployment.targetHost = "router.satanic.link";
  deployment.targetUser = "grw";

  system.stateVersion = "24.11";

  sconfig.gcp-ddns = {
    enable = true;
    aRecords = ["satanic.link"];
    aaaaRecords = ["satanic.link"];
  };

  imports = with inputs.nixos-hardware.nixosModules; [
    common-cpu-amd
    common-gpu-amd

    # ../../../profiles/headless.nix
    ../../../profiles/uefi-boot.nix
    ../../../profiles/radeon.nix
    ../../../profiles/zfs.nix
    ../../../profiles/common.nix
    ../../../profiles/home.nix
    ../../../profiles/router/linux.nix
    ../../../profiles/router/services.nix
    ../../../profiles/router/ap.nix
    ../../../profiles/router/wireguard.nix

    ../../../services/buildfarm-slave.nix
    ../../../containers/unifi.nix
    ../../../services/p2pool.nix
    ../../../services/p2pool-exporter.nix
    ../../../services/home-assistant/default.nix
  ];

  systemd.network.networks."20-nanokvm" = {
    matchConfig.Driver = "rndis_host";
    address = [
      "10.86.167.2/24"
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv6PrivacyExtensions = false;
      IPv6Forwarding = false;
      IgnoreCarrierLoss = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  services.redis.servers.p2pool = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
  };

  services.opentelemetry-collector = {
    enable = true;
    configFile = pkgs.writeText "otel-collector-config.yaml" ''
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 127.0.0.1:4317
            http:
              endpoint: 127.0.0.1:4318

      processors:
        batch:

      exporters:
        debug:
          verbosity: detailed
        prometheus:
          endpoint: 0.0.0.0:8889
          resource_to_telemetry_conversion:
            enabled: true

      service:
        pipelines:
          traces:
            receivers: [otlp]
            processors: [batch]
            exporters: [debug]
          metrics:
            receivers: [otlp]
            processors: [batch]
            exporters: [debug, prometheus]
          logs:
            receivers: [otlp]
            processors: [batch]
            exporters: [debug]
    '';
    package = pkgs.opentelemetry-collector-contrib;
  };

  services.go2rtc = {
    enable = true;
    settings = {
      homekit = {
        esp32-s3-eth-01 = [];
        esp32-s3-eth-02 = [];
      };
      streams = {
        esp32-s3-eth-01 = [
          "http://esp32-s3-eth-01.lan.satanic.link:8000"
          # "ffmpeg:esp32-s3-eth-02#video=h264#hardware#raw=-avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -strict experimental -fflags +genpts+discardcorrupt -use_wallclock_as_timestamps 1"
        ];
        esp32-s3-eth-02 = [
          "http://esp32-s3-eth-02.lan.satanic.link:8000"
          # "ffmpeg:esp32-s3-eth-02#video=h264#hardware#raw=-avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -strict experimental -fflags +genpts+discardcorrupt -use_wallclock_as_timestamps 1"
        ];
      };
    };
  };

  # services.nginx.enable = lib.mkForce false; # nixos module enables this by default
  # networking.hosts = {
  #   "127.0.0.1" = ["frigate.satanic.link"];
  # };

  services.nginx.virtualHosts.${config.services.frigate.hostname} = {
    listen = [
      {
        addr = "192.168.23.1";
        port = 8009;
        ssl = false;
      }
    ];
  };

  services.frigate = {
    enable = true;
    hostname = "frigate.satanic.link";
    vaapiDriver = "radeonsi";
    # checkConfig = false;
    settings = {
      mqtt = {
        enabled = true;
        host = "rw@127.0.0.1";
      };
      # ffmpeg = {
      #   hwaccel_args = [];
      # };
      cameras = {
        esp32-s3-eth-01.ffmpeg = {
          input_args = "-avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -strict experimental -fflags +genpts+discardcorrupt -use_wallclock_as_timestamps 1 -c:v mjpeg";
          inputs = [
            {
              path = "http://127.0.0.1:1984/api/stream.mjpeg?src=esp32-s3-eth-01";
              roles = ["detect" "record"];
            }
          ];
        };
        esp32-s3-eth-02.ffmpeg = {
          input_args = "-avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -strict experimental -fflags +genpts+discardcorrupt -use_wallclock_as_timestamps 1 -c:v mjpeg";
          inputs = [
            {
              path = "http://127.0.0.1:1984/api/stream.mjpeg?src=esp32-s3-eth-02";
              roles = ["detect" "record"];
            }
          ];
        };
      };
    };
  };

  services = {
    iperf3 = {
      enable = true;
      openFirewall = true;
    };
    hardware.bolt.enable = true;
  };

  networking.hosts = {
    "127.0.0.1" = ["localhost" "satanic.link" "router.satanic.link" "frigate.satanic.link"];
    "192.168.23.8" = ["trex.satanic.link"];
  };

  boot.initrd.kernelModules = [
    "nf_tables"
    "nft_compat"
    "igc"
    "ixgbe"
    "vfio"
    "mlx5_core"
  ];

  fileSystems."/" = {
    device = "zpool/root/nixos-router";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/5826-D605";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  networking = {
    hostName = "router";
    hostId = lib.mkForce "deadbeef";
    enableIPv6 = true;
  };
}
