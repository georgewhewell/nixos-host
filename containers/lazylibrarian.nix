{ config, pkgs, ... }:

{

  systemd.services."container@librarian" = {
    bindsTo = [ "mnt-Media.mount" ];
    after = [ "mnt-Media.mount" ];
  };

  containers.librarian = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      /* "/var/lib/librarian" = {
        hostPath = "/var/lib/librarian";
        isReadOnly = false;
      }; */
      "/mnt/Media" = {
        hostPath = "/mnt/Media";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];

      networking.hostName = "librarian";

      virtualisation.docker.enable = true;
      /* -v <path to data>:/config \
      -v <path to downloads>:/downloads \
      -v <path to data>:/books \ */
      systemd.services.geth = {
        description = "geth Service";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "network-online.target "];

        serviceConfig = {
          script = ''
            ${pkgs.docker}/bin/docker run --rm \
              -e TZ=Europe/London \
              -e DOCKER_MODS=linuxserver/calibre-web:calibre|linuxserver/mods:lazylibrarian-ffmpeg `#optional` \
              --net host \
              --restart unless-stopped \
              ghcr.io/linuxserver/lazylibrarian
          '';
        };
      };

    };
  };
}
