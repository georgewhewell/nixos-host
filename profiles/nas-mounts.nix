{network, ...}: let
  trexIp = network.primaryIp network.hosts.trex;
  options = [
    "nofail"
    "_netdev"
    "x-systemd.automount"
    "x-systemd.after=network-online.target"
    "x-systemd.requires=network-online.target"
    "rsize=32768"
    "wsize=32768"
    "nconnect=4"
  ];
in {
  services.rpcbind.enable = true;

  fileSystems."/mnt/Home" = {
    device = "${trexIp}:/home";
    fsType = "nfs";
    inherit options;
  };

  fileSystems."/mnt/Media" = {
    device = "${trexIp}:/media";
    fsType = "nfs";
    inherit options;
  };
}
