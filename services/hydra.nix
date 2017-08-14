{ config, lib, pkgs, boot, networking, containers, ... }:

let
  # make sure we always have the latest module
  /*hydra = pkgs.fetchgit {
    url = https://github.com/NixOS/hydra;
    rev = "refs/heads/master";
  };*/
in {

  fileSystems."/var/lib/hydra" =
    { device = "bpool/root/hydra";
      fsType = "zfs";
    };

  networking.firewall.allowedTCPPorts = [ 3000 ];

  require = [ ../hydra/hydra-module.nix ];

  services.hydra-dev = {
    enable = true;
    dbi = "dbi:Pg:dbname=hydra;host=localhost;user=hydra;password=hydra";
    hydraURL = "http://hydra.4a/";
    listenHost = "0.0.0.0";
    port = 3000;
    minimumDiskFree = 5;  # in GB
    minimumDiskFreeEvaluator = 2;
    notificationSender = "hydra@yourserver.com";
    logo = null;
    debugServer = false;
  };

  nix.distributedBuilds = true;
  nix.buildMachines = [
     {
      hostName = "localhost";
      maxJobs = "12";
      system = "x86_64-linux";
    }
    { hostName = "odroid-c2.4a";
      sshUser = "buildfarm";
      sshKey = "/etc/nix/buildfarm";
      system = "aarch64-linux";
      maxJobs = 1;
    }
];

systemd.services.lumi-hydra-setup = {
wantedBy = [ "multi-user.target" ];
requires = [ "hydra-init.service" "postgresql.service" ];
after = [ "hydra-init.service" "postgresql.service" ];
environment = config.systemd.services.hydra-init.environment;
path = [ config.services.hydra.package ];
script =
let hydraHome = config.users.users.hydra.home;
hydraQueueRunnerHome = config.users.users.hydra-queue-runner.home;
in ''
hydra-create-user grw \
--full-name 'georgewhewell' \
--email-address 'georgerw@gmail.com' \
--password 'hydra' \
--role admin
'';
serviceConfig = {
Type = "oneshot";
RemainAfterExit = true;
};
};

  services.postgresql.enable = true;

  networking.defaultMailServer = {
    directDelivery = true;
    hostName = "nixhost";
    domain = "4a";
  };

}
