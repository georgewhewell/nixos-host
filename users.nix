{ config, lib, pkgs, ... }:

{
  users.extraUsers.grw = {
    extraGroups = ["wheel" "libvirtd" "docker"];
    isNormalUser = true;
     openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHCp/KhshTrp+p1TQOp3PZfwvj+pAGzm7Z4tbRYImpHNS9octfJ4sSmL4X4YQSu4PbpM/9Jo5UzVPpCRpD6OOiA= grw@nixhost"
      "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAARQekrodVEAhnQ+N49sazaTKtlXmu4riUmArsY7H01zHHtVR+ISM8zvq0yQVbTNw2VRJ4sfKUjqXLM2FGUIHuN7AAQWuajvDbqjBC+IBr5+kKVdFMz1sF/T0Ov9R68k3ebBw7W/lsegdB479IBq+9CHN5HYnSMLu+rrL/zsvnXISuidQ== grw@Georges-Mac-Pro"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBZ7a3vc5ex0sSTz8uitNrf96k5iURfRL8e9AoM93Yw1oKk5CD4mOZLOb7Av7SwFLtvgGMTnpLsxuusj2QoGTCk= grw@h9fp4whfi.local"
    ];
  };

   security.sudo.wheelNeedsPassword = false;
}
