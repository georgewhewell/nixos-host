{ config, lib, pkgs, ... }:

{

  security.acme.certs."git.satanic.link" = {
     email = "georgerw@gmail.com";
     postRun = ''systemctl reload nginx.service'';
  };

  networking.firewall.allowedTCPPorts = [ 2222 ];

  services.gogs = {
    enable = true;
    database = {
      type = "postgres";
      host = "127.0.0.1";
      port = 5432;
      passwordFile = "/etc/nix/gogs-pw";
    };
    domain = "git.satanic.link";
    rootUrl = "https://git.satanic.link";
    httpPort = 3001;
    cookieSecure = true;
    extraConfig = ''
      [server]
      START_SSH_SERVER = true
      SSH_PORT = 2222
      SSH_LISTEN_PORT = 2222
      
      OFFLINE_MODE = true
      DISABLE_REGISTRATION = true
      REQUIRE_SIGNIN_VIEW = true
    '';
  };

  services.nginx.virtualHosts."git.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3001";
    };
  };
}
