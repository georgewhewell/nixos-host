{ config, lib, pkgs, ... }:

{
  services.udev.extraRules = ''
     ATTRS{idVendor}=="1852", ATTRS{idProduct}=="7022", MODE="666", RUN+="/run/current-system/sw/bin/virsh attach-device ElCapitan /etc/USB_Audio.xml"
     ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="17a0", MODE="666", RUN+="/run/current-system/sw/bin/virsh attach-device ElCapitan /etc/Xonar.xml"
     ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c247", MODE="666", RUN+="/run/current-system/sw/bin/virsh attach-device ElCapitan /etc/Logitech_G100s.xml"
     ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c31d", MODE="666", RUN+="/run/current-system/sw/bin/virsh attach-device ElCapitan /etc/Logitech_Keyboard.xml"
     ATTRS{idVendor}=="0b05", ATTRS{idProduct}=="17cb", MODE="666", RUN+="/run/current-system/sw/bin/virsh attach-device ElCapitan /etc/ASUS_Bluetooth.xml"
     ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="12a8", MODE="666", RUN+="/run/current-system/sw/bin/virsh attach-device ElCapitan /etc/iPhone_5.xml"
   '';

  environment.etc."Logitech_Keyboard.xml".text = ''
<hostdev mode='subsystem' type='usb'>
  <source>
    <vendor id='0x046d'/>
    <product id='0xc31d'/>
  </source>
</hostdev>
  '';
  environment.etc."USB_Audio.xml".text = ''
<hostdev mode='subsystem' type='usb'>
  <source>
    <vendor id='0x1852'/>
    <product id='0x7022'/>
  </source>
</hostdev>
  '';
  environment.etc."Xonar.xml".text = ''
<hostdev mode='subsystem' type='usb'>
  <source>
    <vendor id='0x0b05'/>
    <product id='0x17a0'/>
  </source>
</hostdev>
  '';
  environment.etc."Logitech_G100s.xml".text = ''
<hostdev mode='subsystem' type='usb'>
  <source>
    <vendor id='0x046d'/>
    <product id='0xc247'/>
  </source>
</hostdev>
  '';
  environment.etc."ASUS_Bluetooth.xml".text = ''
<hostdev mode='subsystem' type='usb'>
  <source>
    <vendor id='0x0b05'/>
    <product id='0x17cb'/>
  </source>
</hostdev>
  '';
  environment.etc."iPhone_5.xml".text = ''
<hostdev mode='subsystem' type='usb'>
  <source>
    <vendor id='0x05ac'/>
    <product id='0x12a8'/>
  </source>
  <port>1</port>
</hostdev>
  '';
}
