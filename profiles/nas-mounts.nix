{...}: let
  options = ["nofail" "rsize=32768" "wsize=32768" "nconnect=4"];
in {
  services.rpcbind.enable = true;

  # fileSystems."/mnt/Home" = {
  #   device = "192.168.23.8:/export/home";
  #   fsType = "nfs";
  #   inherit options;
  # };

  fileSystems."/mnt/Media" = {
    device = "192.168.23.8:/export/media";
    fsType = "nfs";
    inherit options;
  };
}
