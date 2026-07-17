{config, network, ...}: {
  services.go2rtc = {
    enable = true;
    settings = {
      homekit = {
        esp32-s3-eth-01 = [];
        esp32-s3-eth-02 = [];
        esp32-p4-wifi = [];
        esp32-p4-eth-01 = [];
      };
      streams = {
        esp32-s3-eth-01 = [
          "http://${network.fqdn "esp32-s3-eth-01"}:8080"
        ];
        esp32-p4-wifi = [
          "http://${network.fqdn "esp32-p4-wifi"}:8080"
        ];
        esp32-p4-eth-01 = [
          "http://${network.fqdn "esp32-p4-eth-01"}:8080"
        ];
      };
    };
  };

  services.nginx.virtualHosts.${config.services.frigate.hostname} = {
    listen = [
      {
        addr = network.routerIp;
        port = 8009;
        ssl = false;
      }
    ];
  };

  systemd.services.nginx = {
    after = ["network-online.target"];
    wants = ["network-online.target"];
  };

  systemd.services.frigate.serviceConfig = {
    # Frigate sometimes hangs during SIGTERM shutdown while unwinding ffmpeg
    # workers. Do not let it hold router reboots for systemd's 90s default.
    TimeoutStopSec = "15s";
  };

  services.frigate = {
    enable = true;
    hostname = network.publicFqdn "frigate";
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
              roles = ["record"];
            }
          ];
        };
        esp32-p4-wifi.ffmpeg = {
          input_args = "-avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -strict experimental -fflags +genpts+discardcorrupt -use_wallclock_as_timestamps 1 -c:v mjpeg";
          inputs = [
            {
              path = "http://127.0.0.1:1984/api/stream.mjpeg?src=esp32-p4-wifi";
              roles = ["record"];
            }
          ];
        };
        esp32-p4-eth-01.ffmpeg = {
          input_args = "-avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -strict experimental -fflags +genpts+discardcorrupt -use_wallclock_as_timestamps 1 -c:v mjpeg";
          inputs = [
            {
              path = "http://127.0.0.1:1984/api/stream.mjpeg?src=esp32-p4-eth-01";
              roles = ["record"];
            }
          ];
        };
      };
    };
  };
}
