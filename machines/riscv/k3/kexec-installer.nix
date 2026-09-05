{
  inputs,
  lib,
  network,
  ...
}: let
  sshKeys = import ../../../profiles/ssh-keys.nix;
  self = network.hosts.k3;
  lanMacs = [self.mac] ++ (self.extraMacs or []);
in {
  imports = [
    inputs.nanokvm.nixosModules.boards.k3."pico-itx"."kexec-installer"
    ../../../profiles/fleet-core.nix
  ];

  sconfig.profile = "server";
  spacemit.k3.authorizedKeys = builtins.attrValues sshKeys;
  spacemit.k3.kexecInstallerName = "nixos-kexec-installer-k3";

  networking.firewall.enable = lib.mkForce false;
  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.network.networks."20-enP2p1s0" = {
    matchConfig.MACAddress = lanMacs;
    address = [(network.cidrOf "lan" self.addresses.lan)];
    dns = [network.dnsIp];
    routes = [
      {
        Gateway = network.gatewayIp "lan";
        Metric = 10;
      }
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
    };
    linkConfig.RequiredForOnline = "no";
  };
}
