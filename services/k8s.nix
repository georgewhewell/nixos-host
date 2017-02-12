{ config, lib, pkgs, ... }:

{
  imports = [
     ../packages/kubernetes.svc.nix
  ];
 
  networking = {
    extraHosts = "10.10.0.1 nixserve";
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

  services.kubernetes_15 = {
    package = pkgs.kubernetes_15;
    roles = ["master" "node"];
    apiserver = {
     port = 9090;
     securePort = 8443;
     tlsKeyFile = "/var/run/kubernetes/server.key";
     tlsCertFile = "/var/run/kubernetes/server.cert";
     clientCaFile = "/var/run/kubernetes/ca.crt";
     kubeletClientCaFile = "/var/run/kubernetes/ca.crt";
     kubeletClientKeyFile = "/var/run/kubernetes/server.key";
     kubeletClientCertFile = "/var/run/kubernetes/server.cert";
     serviceAccountKeyFile = "/var/run/kubernetes/server.key";
    };
    kubelet = {
     tlsKeyFile = "/var/run/kubernetes/server.key";
     tlsCertFile = "/var/run/kubernetes/server.cert";
    };
    controllerManager = {
     serviceAccountKeyFile = "/var/run/kubernetes/server.key"; 
     rootCaFile = "/var/run/kubernetes/ca.crt";
    };
    proxy = {
     extraOpts = ''
      --cluster-cidr=10.10.10.10/24
     '';
    };
  };

}
