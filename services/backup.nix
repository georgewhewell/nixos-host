{ config, lib, pkgs, ... }:

{
      systemd.services.spindown_hdd =
      {
        description = "spin down usb hdd";
        serviceConfig = {
          ExecStart = "${pkgs.sdparm}/bin/sdparm --command=stop --readonly /dev/disk/by-id/usb-Seagate_Expansion_Desk_NA4K8NA4-0:0";
          Type = "oneshot";
        };
        startAt = "*:18";
      };
}
