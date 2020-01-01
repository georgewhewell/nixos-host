{ config, lib, pkgs, boot, networking, containers, ... }:

{

  systemd.services."hydra-init".after = [ "network-online.target" ];

  services.nginx.virtualHosts."hydra.satanic.link" = {
     forceSSL = true;
     enableACME = true;
     locations."/" = {
       proxyPass = "http://127.0.0.1:3000";
       extraConfig = ''
          proxy_redirect          off;
          proxy_connect_timeout   90;
          proxy_send_timeout      90;
          proxy_read_timeout      90;
          proxy_http_version      1.0;

          proxy_set_header        Host $host;
          proxy_set_header        X-Real-IP $remote_addr;
          proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header        X-Forwarded-Proto $scheme;
          proxy_set_header        X-Forwarded-Host $host;
          proxy_set_header        X-Forwarded-Server $host;
          proxy_set_header        Accept-Encoding "";
       '';
     };
  };

  services.hydra = {
    enable = true;
    dbi = "dbi:Pg:dbname=hydra";
    hydraURL = "https://hydra.satanic.link/";
    listenHost = "127.0.0.1";
    port = 3000;
    minimumDiskFree = 5;  # in GB
    minimumDiskFreeEvaluator = 2;
    notificationSender = "hydra@satanic.link";
    logo = null;
    debugServer = false;
    useSubstitutes = true;
    extraConfig = ''
      using_frontend_proxy 1
      base_uri https://hydra.satanic.link
      max_output_size = 4294967296
      binary_cache_secret_key_file /etc/nix/signing-key.sec
    '';
  };

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "fuckup.lan";
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      maxJobs = 4;
      speedFactor = 2;
      systems = [ "x86_64-linux" "i686-linux" ];
    }
    {
      hostName = "nixhost.lan";
      supportedFeatures = [ "kvm" "nixos-test" "big-parallel" ];
      sshUser = "root";
      sshKey = "/etc/nix/buildfarm";
      maxJobs = 8;
      speedFactor = 1;
      systems = ["x86_64-linux" "i686-linux"];
    }
  ];

}
