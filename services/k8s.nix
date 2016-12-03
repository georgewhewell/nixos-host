{ config, lib, pkgs, ... }:

{
  networking = {
    bridges = {
      cbr0.interfaces = [];
    };
    interfaces.cbr0 = {};
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "zfs";
    socketActivation = false;
    extraOptions = "-H tcp://127.0.0.1:2375 -H unix:///var/run/docker.sock --iptables=false --ip-masq=false -b cbr0";
  };

  services.kubernetes.roles = ["master" "node"];

}
