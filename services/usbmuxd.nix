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

  services.udev.extraRules = ''
    ENV{DEVTYPE}=="usb_device", ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="129[0-9abcef]", RUN+="${pkgs.ipad_charge}/bin/ipad_charge"
    ENV{DEVTYPE}=="usb_device", ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="12a[0-9ab]", RUN+="${pkgs.ipad_charge}/bin/ipad_charge"
    ENV{DEVTYPE}=="usb_device", ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0fca", ATTR{idProduct}=="8014", RUN+="${pkgs.ipad_charge}/bin/ipad_charge"
  '';
}
