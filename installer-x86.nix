{config, pkgs, ...}:
{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
    ./profiles/common.nix
    ./profiles/xserver.nix
    ./profiles/gpg-yubikey.nix
  ];

  boot.initrd.supportedFilesystems = [
    "zfs"
    "nfs"
  ];

  networking.hostName = "nixos-installer";
  users.extraUsers.grw.initialHashedPassword =
    "$6$1PuMimFFMB6qB$BoI9OhQTOAfbn5Om9Q36KuIoG5xWyWoA7NoLecnvFUQ36uBYufPN9LIkkhgIZD7RiWpP88SDM1FuJ0l44bMvP1";
}
