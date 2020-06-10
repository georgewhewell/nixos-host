{ config, lib, pkgs, ... }:

{
  imports = [
    ../packages/kubernetes.svc.nix
  ];

  networking = {
    extraHosts = "10.10.0.1 nixserve";
    bridges = {
      cbr0.interfaces = [ ];
    };

    interfaces.cbr0 = {
      ipAddress = "10.10.0.1";
      prefixLength = 24;
    };

    firewall.allowedTCPPorts = [ 80 443 ];
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "zfs";
    extraOptions = "-b cbr0";
  };

  services.kubernetes_15 = {
    package = pkgs.kubernetes_15;
    roles = [ "master" "node" ];
    apiserver = {
      port = 6060;
      securePort = 8443;
      tlsKeyFile = "/var/lib/kube-certs/server.key";
      tlsCertFile = "/var/lib/kube-certs/server.cert";
      clientCaFile = "/var/lib/kube-certs/ca.crt";
      kubeletClientCaFile = "/var/lib/kube-certs/ca.crt";
      kubeletClientKeyFile = "/var/lib/kube-certs/server.key";
      kubeletClientCertFile = "/var/lib/kube-certs/server.cert";
      serviceAccountKeyFile = "/var/lib/kube-certs/server.key";
    };
    kubelet = {
      allowPrivileged = true;
      tlsKeyFile = "/var/lib/kube-certs/server.key";
      tlsCertFile = "/var/lib/kube-certs/server.cert";
    };
    controllerManager = {
      serviceAccountKeyFile = "/var/lib/kube-certs/server.key";
      rootCaFile = "/var/lib/kube-certs/ca.crt";
    };
  };

}
