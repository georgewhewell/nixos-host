{ config, lib, pkgs, ... }:

{
  services.transmission.enable = true;
  services.transmission.settings = {
    rpc-whitelist = "127.0.0.1,192.168.*.*,172.*.*.*";
    download-dir = "/storage/downloads";
    umask = 0;
  };

}
