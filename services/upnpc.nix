{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    miniupnpc
  ];
  systemd.services.upnpc_map =
    {
      description = "Run upnpc to redirect port 22";
      serviceConfig.ExecStart = "${pkgs.miniupnpc}/bin/upnpc -r 22 tcp";
      startAt = "*:0";
      serviceConfig.Type = "oneshot";
    };

}
