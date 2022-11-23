{ config, pkgs, ... }:

{

  services.mosquitto = {
    enable = true;
    listeners = [{
      address = "0.0.0.0";
      users = {
        "rw" = {
          acl = [ "readwrite #" ];
          password = "i503Myc3b6wOYKM8fDwypUstI";
        };
      };
    }];
  };

}
