{ config, lib, pkgs, ... }:

{
  networking = {
    bridges = {
      cbr0.interfaces = [];
    };
    interfaces.cbr0 = {
      ipAddress = "10.10.0.1";
      prefixLength = 24;
    };
  };

  services.etcd = {
    listenPeerUrls = ["http://0.0.0.0:7001"];
    initialAdvertisePeerUrls = ["http://localhost:7001"];
    initialCluster = ["master=http://localhost:7001"];
  };

  services.dockerRegistry.enable = true;
  services.dockerRegistry.host = "0.0.0.0";
  services.dockerRegistry.port = 5000;

  systemd.services.kubelet = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStartPre = [
        ''-${pkgs.docker}/bin/docker rm -f kubelet''
      ];
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --volume=/:/rootfs:ro \
        --volume=/sys:/sys:ro \
        --volume=/dev:/dev \
        --volume=/var/lib/docker/:/var/lib/docker:ro \
        --volume=/var/lib/kubelet/:/var/lib/kubelet:rw \
        --volume=/var/run:/var/run:rw \
        --net=host \
        --pid=host \
        --privileged=true \
        --name k8s_master \
        gcr.io/google_containers/hyperkube:v1.1.3 \
          /hyperkube kubelet \
            --containerized \
            --hostname-override="127.0.0.1" \
            --address="0.0.0.0" \
            --api-servers=http://localhost:8080
            --api-servers=http://localhost:8080 \
            --config=/etc/kubernetes/manifests'';
      ExecStop = ''${pkgs.docker}/bin/docker stop k8s_master'';
    };
  };
}
