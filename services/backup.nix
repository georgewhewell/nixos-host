{ config, lib, pkgs, ... }:

{
      systemd.services.media_backup =
      {
        description = "media backup";
        serviceConfig.ExecStart = "${pkgs.rsync}/bin/rsync -rtvu --delete-delay --progress /storage/Media /backups/";
        startAt = "08:00";
        serviceConfig.Type = "oneshot";
      };

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
