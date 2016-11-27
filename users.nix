{ config, lib, pkgs, ... }:

{
  users.extraUsers.grw = {
    extraGroups = ["wheel" "libvirtd" "docker" "transmission"];
    isNormalUser = true;
     openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHCp/KhshTrp+p1TQOp3PZfwvj+pAGzm7Z4tbRYImpHNS9octfJ4sSmL4X4YQSu4PbpM/9Jo5UzVPpCRpD6OOiA= grw@nixhost"
      "ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAARQekrodVEAhnQ+N49sazaTKtlXmu4riUmArsY7H01zHHtVR+ISM8zvq0yQVbTNw2VRJ4sfKUjqXLM2FGUIHuN7AAQWuajvDbqjBC+IBr5+kKVdFMz1sF/T0Ov9R68k3ebBw7W/lsegdB479IBq+9CHN5HYnSMLu+rrL/zsvnXISuidQ== grw@Georges-Mac-Pro"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBZ7a3vc5ex0sSTz8uitNrf96k5iURfRL8e9AoM93Yw1oKk5CD4mOZLOb7Av7SwFLtvgGMTnpLsxuusj2QoGTCk= grw@h9fp4whfi.local"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/yARn1J0K+z8kdhLGxZgCe0kIrCJg5o7DC0oITmbzE3YKrubFVNn7zHkwzRw0b8kjfZFIxFbo5toOFCO0VN5biujrWbutzlLjTnFP0YqoL47XD58gU+TWZb/9qoV1Yjj1OUXJ+93ZTGjXGyZ+0FDtp84lFoDgSvBXf8C742g4gm6KkXYFfGYMz8LRKSnXYpeuMu18UdZVo33m8aweTvZ+m7riD6YCJILNIPFIvVExg+UNzOh4t0Hrj+O5ir9NNCqQeu633yXKlOMShbQVmmPZfrxpg24Fv5orX/pZZM+fHB94yO5wunlzxVsF5GVjCKJL5Gj/SqCRePohDiePNdP/ grw@fuckup"
    ];
  };

   security.sudo.wheelNeedsPassword = false;
}
