{ config, lib, pkgs, ... }:

{
  systemd.services.jaeger-all-in-one = {
    enable = true;
    description = "bar";
    unitConfig = {
      Type = "simple";
    };
    serviceConfig = {
      ExecStart = ''
        ${pkgs.docker}/bin/docker run \
          --rm \
          --name jaeger \
          -e COLLECTOR_ZIPKIN_HOST_PORT=:9411 \
          --net host \
          jaegertracing/all-in-one:latest
      '';
    };
    wantedBy = [ "multi-user.target" ];
  };
}
