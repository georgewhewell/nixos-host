{ pkgs, ... }:

# OTLP collector for the AI CLI tools (claude-code, grok, gemini, codex, ...).
# Receives OTLP on :4317 (gRPC) / :4318 (HTTP) from anywhere on the LAN and
# writes metrics into the local VictoriaMetrics for the home dashboards.
# Agent telemetry lives here and only here; the hellas services keep their own
# separate pipeline to the infra collector on ax102 (services.hellas.otel).
{
  services.opentelemetry-collector = {
    enable = true;
    package = pkgs.opentelemetry-collector-contrib;
    settings = {
      receivers.otlp.protocols = {
        grpc.endpoint = "0.0.0.0:4317";
        http.endpoint = "0.0.0.0:4318";
      };

      processors = {
        batch = {
          send_batch_size = 1024;
          timeout = "10s";
        };
        # claude-code (and possibly others) default to delta temporality,
        # which the prometheus remote-write path cannot represent — convert.
        deltatocumulative = { };
      };

      exporters = {
        prometheusremotewrite = {
          endpoint = "http://127.0.0.1:8428/api/v1/write";
          # Fold resource attributes (service.name, etc.) into metric labels so
          # per-tool and per-model breakdowns survive the conversion.
          resource_to_telemetry_conversion.enabled = true;
        };
        nop = { };
      };

      service.pipelines = {
        metrics = {
          receivers = [ "otlp" ];
          processors = [ "deltatocumulative" "batch" ];
          exporters = [ "prometheusremotewrite" ];
        };
        # Accept-and-drop so clients configured with a logs exporter don't
        # see errors; nothing consumes CLI logs locally.
        logs = {
          receivers = [ "otlp" ];
          exporters = [ "nop" ];
        };
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 4317 4318 ];
}
