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

  systemd.services.hyperkube = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      TimeoutStartSec = 0;
      Restart = "always";
      ExecStart = ''${pkgs.docker}/bin/docker run \
        --rm \
        --volume=/:/rootfs:ro \
        --volume=/sys:/sys:rw \
        --volume=/sys:/sys:ro \
        --volume=/var/lib/docker/:/var/lib/docker:rw \
        --volume=/var/lib/kubelet/:/var/lib/kubelet:rw \
        --volume=/var/run:/var/run:rw \
        --net=host \
        --pid=host \
        --privileged \
        gcr.io/google_containers/hyperkube-amd64:v1.3.0-alpha.5 \
          /hyperkube kubelet \
        --privileged=true \
        --name kubelet \
        gcr.io/google_containers/hyperkube-amd64:v1.3.0-alpha.3 \
          /hyperkube kubelet \
            --hostname-override="127.0.0.1" \
            --address="0.0.0.0" \
            --hostname-override="127.0.0.1" \
            --cluster-dns=10.0.0.10 \
            --cluster-domain=cluster.local \
            --api-servers=http://localhost:8080 \
            --config=/etc/kubernetes/manifests \
            --allow-privileged=true --v=2'';
    };
  };
}
