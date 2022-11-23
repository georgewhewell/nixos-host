{ config, pkgs, options, ... }:

let
  mainnet = {
    metrics = 6060;
    p2p = 30030;
    http = 8545;
    ws = 8546;
  };
  erigon = {
    metrics = 6070;
    p2p = 30070;
    http = 8575;
    ws = 8576;
  };
  matic = {
    # metrics = 6061;
    p2p = 30031;
    http = 8145;
    ws = 8146;
  };
  optimism = {
    # metrics = 6061;
    p2p = 30032;
    http = 9991;
    ws = 9992;
  };
in
{

  imports =
    [
      ../../../profiles/common.nix
      ../../../profiles/development.nix

      ../../../profiles/headless.nix
      ../../../profiles/hetzner-dev.nix
    ];

  deployment = {
    targetHost = "65.21.122.161";
    targetUser = "root";
  };

  networking.hostName = "ax101";

  sconfig = {
    profile = "server";
    hetzner = {
      enable = true;
      luksUuid = "41a6ccbb-9aa5-4211-8743-22aaea85ce9f";
      interface = "enp7s0";
      ipv4 = {
        address = "65.21.122.161";
        gateway = "65.21.122.129";
        netmask = "255.255.255.0";
      };
      ipv6 = {
        address = "2a01:4f9:3b:4b19::1";
      };
      wgAddress = "192.168.24.2";
    };
    home-manager = {
      enable = true;
      enableVscodeServer = true;
    };
  };

  services.geth = {
    mainnet = with mainnet; {
      enable = true;
      maxpeers = 128;
      syncmode = "snap";
      gcmode = "full";
      metrics = {
        enable = true;
        address = "0.0.0.0";
        port = metrics;
      };
      port = p2p;
      http = {
        enable = true;
        port = http;
        address = "0.0.0.0"; # firewalled
      };
      websocket = {
        enable = true;
        port = ws;
        address = "0.0.0.0"; # firewalled
      };
      extraArgs = [
        "--cache=16000"
        "--http.vhosts=eth-mainnet.ax101.satanic.link,eth-mainnet-ws.ax101.satanic.link,localhost"
      ];
    };
  };

  services.erigon = {
    mainnet = with erigon; {
      enable = true;
      maxpeers = 128;
      syncmode = "snap";
      gcmode = "full";
      metrics = {
        enable = true;
        address = "0.0.0.0";
        port = metrics;
      };
      port = p2p;
      http = {
        enable = true;
        port = http;
        address = "0.0.0.0"; # firewalled
      };
      websocket = {
        enable = true;
        port = ws;
        address = "0.0.0.0"; # firewalled
      };
      extraArgs = [
        "--http.api=eth,erigon,web3,net"
        # "--cache=16000"
        # "--http.vhosts=eth-mainnet-erigon.ax101.satanic.link,eth-mainnet-erigon-ws.ax101.satanic.link,localhost"
      ];
    };
  };

  sconfig.optimism = {
    enable = true;
  };

  networking = {
    firewall.allowedTCPPorts = [ mainnet.p2p matic.p2p optimism.p2p 80 443 ];
    firewall.allowedUDPPorts = [ mainnet.p2p matic.p2p optimism.p2p ];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "georgerw@gmail.com";
  };

  services.uniswap = {
    enable = false;
    databaseDsn = "postgresql:///uniswap";
    gethDsn = "ws://localhost:8546";
    bscGethDsn = "ws://localhost:8546";
  };

  # environment.systemPackages = [ pkgs.optimism-dtl.contracts ];
  services.nginx = {
    enable = true;
    statusPage = true;
    recommendedTlsSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."eth-mainnet.ax101.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString mainnet.http}";
      };
    };

    virtualHosts."eth-mainnet-ws.ax101.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString mainnet.ws}";
        proxyWebsockets = true;
      };
    };

    virtualHosts."matic-mainnet.ax101.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString matic.http}";
      };
    };

    virtualHosts."matic-mainnet-ws.ax101.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString matic.ws}";
        proxyWebsockets = true;
      };
    };

    virtualHosts."optimism-mainnet.ax101.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString optimism.http}";
      };
    };

    virtualHosts."optimism-mainnet-ws.ax101.satanic.link" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://localhost:${toString optimism.ws}";
        proxyWebsockets = true;
      };
    };
  };

}
