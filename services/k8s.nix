{ config, lib, pkgs, ... }:

{
  networking = {
    bridges = {
      cbr0.interfaces = [];
    };
    interfaces.cbr0 = {};
    firewall.trustedInterfaces = [ "crb0" ];
    firewall.checkReversePath = false;
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "zfs";
    extraOptions = "--iptables=false --ip-masq=false -b cbr0";
  };

  /*environment.variables = {
    ETCDCTL_CERT_FILE = "${etcd_client_cert}";
    ETCDCTL_KEY_FILE = "${etcd_client_key}";
    ETCDCTL_CA_FILE = "${ca_pem}";
    ETCDCTL_PEERS = "https://127.0.0.1:2379";
  };*/

  services.kubernetes = {
    roles = ["master" "node"];
  };

}
