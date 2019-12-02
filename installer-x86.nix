{ config, lib, pkgs, ...}:

{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
    ./profiles/common.nix
    ./profiles/gpg-yubikey.nix
  ];

  boot.initrd.supportedFilesystems = [
    "zfs"
    "nfs"
    "f2fs"
  ];

  environment.systemPackages = with pkgs; [
    nfsUtils
  ];

  hardware.enableAllFirmware = true;
  networking.wireless.enable = false;

  networking = {
    hostName = "nixos-installer";
    networkmanager = {
      enable = true;
      wifi = {
        backend = "iwd";
      };
    };
  };

  hardware.bluetooth.enable = true;
  services.usbmuxd.enable = true;

  boot.kernelModules = [ "wl" ];
  boot.blacklistedKernelModules = [
    "b44" "b43" "b43legacy" "ssb" "brcmsmac" "bcma" ];
  boot.extraModulePackages = [
    config.boot.kernelPackages.broadcom_sta
  ];

  users.extraUsers.grw.initialHashedPassword =
    "$6$1PuMimFFMB6qB$BoI9OhQTOAfbn5Om9Q36KuIoG5xWyWoA7NoLecnvFUQ36uBYufPN9LIkkhgIZD7RiWpP88SDM1FuJ0l44bMvP1";

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/yARn1J0K+z8kdhLGxZgCe0kIrCJg5o7DC0oITmbzE3YKrubFVNn7zHkwzRw0b8kjfZFIxFbo5toOFCO0VN5biujrWbutzlLjTnFP0YqoL47XD58gU+TWZb/9qoV1Yjj1OUXJ+93ZTGjXGyZ+0FDtp84lFoDgSvBXf8C742g4gm6KkXYFfGYMz8LRKSnXYpeuMu18UdZVo33m8aweTvZ+m7riD6YCJILNIPFIvVExg+UNzOh4t0Hrj+O5ir9NNCqQeu633yXKlOMShbQVmmPZfrxpg24Fv5orX/pZZM+fHB94yO5wunlzxVsF5GVjCKJL5Gj/SqCRePohDiePNdP/ grw@fuckup"
  ];

  documentation.enable = lib.mkDefault false;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

}
