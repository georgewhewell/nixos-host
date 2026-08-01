{ pkgs, ... }:

# OTLP collector for the AI CLI tools (claude-code, grok, gemini, codex, ...).
# Receives OTLP on :4317 (gRPC) / :4318 (HTTP) from anywhere on the LAN, writes
# metrics into the local VictoriaMetrics for the home dashboards, and forwards
# the full OTLP stream (metrics + logs) to the infra collector on ax102
# (services/monitoring/otel-collector.nix in ../infra), which previously
# received the grok stream directly — so its Loki/Tempo pipelines keep working.
{
  services.opentelemetry-collector = {
    enable = true;
    package = pkgs.opentelemetry-collector-contrib;
    settings = {
      receivers.otlp.protocols = {
        grpc.endpoint = "0.0.0.0:4317";
        http.endpoint = "0.0.0.0:4318";
      };

      processors.batch = {
        send_batch_size = 1024;
        timeout = "10s";
      };

      exporters = {
        prometheusremotewrite = {
          endpoint = "http://127.0.0.1:8428/api/v1/write";
          # Fold resource attributes (service.name, etc.) into metric labels so
          # per-tool and per-model breakdowns survive the conversion.
          resource_to_telemetry_conversion.enabled = true;
        };
        # Forward to the infra collector over the hydra-builders WireGuard.
        # Queue-and-drop rather than backpressure when ax102 is unreachable;
        # the local VictoriaMetrics write is unaffected either way.
        "otlphttp/ax102" = {
          endpoint = "http://10.101.0.2:4318";
          timeout = "5s";
          retry_on_failure.enabled = true;
          sending_queue = {
            enabled = true;
            num_consumers = 2;
            queue_size = 8192;
          };
        };
      };

      service.pipelines = {
        metrics = {
          receivers = [ "otlp" ];
          processors = [ "batch" ];
          exporters = [ "prometheusremotewrite" "otlphttp/ax102" ];
        };
        logs = {
          receivers = [ "otlp" ];
          processors = [ "batch" ];
          exporters = [ "otlphttp/ax102" ];
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 4317 4318 ];
}
