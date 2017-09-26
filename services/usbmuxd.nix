{ pkgs, ...}:

{
  systemd.services.usbmuxd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''
        ${pkgs.usbmuxd}/bin/usbmuxd -f
      '';
    };
  };
}
