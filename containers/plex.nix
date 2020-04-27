{ config, lib, pkgs, boot, networking, containers, ... }:

{
  systemd.services."container@plex".requires = [ "mnt-Media.mount" ];

  containers.plex = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    allowedDevices = [
      { modifier = "rw"; node = "/dev/dri/card0"; }
      { modifier = "rw"; node = "/dev/dri/renderD128"; }
    ];

    bindMounts = {
      "/dev/dri/card0" = {
        hostPath = "/dev/dri/card0";
        isReadOnly = false;
      };
      "/dev/dri/renderD128" = {
        hostPath = "/dev/dri/renderD128";
        isReadOnly = false;
      };
      "/var/lib/plex" = {
        hostPath = "/var/lib/plex";
        isReadOnly = false;
      };
      "/movies" = {
        hostPath = "/mnt/Media/Movies";
        isReadOnly = false;
      };
      "/tv" = {
        hostPath = "/mnt/Media/TV";
        isReadOnly = false;
      };
    };

    config = {
      imports = [ ../profiles/container.nix ];
      networking.hostName = "plex";

      services.avahi = {
        enable = true;
        nssmdns = true;
        publish.addresses = true;
        publish.domain = true;
        publish.enable = true;
        publish.userServices = true;
        publish.workstation = true;
      };

      hardware.opengl = {
        enable = true;
        driSupport = true;
        driSupport32Bit = true;
        extraPackages = with pkgs; [
          libva-full
          vaapiVdpau
          (vaapiIntel.override { enableHybridCodec = true; })
          libvdpau-va-gl
          intel-media-driver
        ];
      };

      nixpkgs.config.allowUnfree = true;
      users.extraUsers.plex.extraGroups = [ "video" "render" ];
      environment.systemPackages = [ pkgs.libva-utils ];

      services.plex = {
        enable = true;
        openFirewall = true;
        dataDir = "/var/lib/plex";
      };

      systemd.services.tvhproxy = let
	tvh-proxy = with pkgs; stdenv.mkDerivation {
	  pname = "tvh_proxy";
	  version = "0.0.1";
	  src = fetchFromGitHub {
	    owner = "jkaberg";
	    repo = "tvhProxy";
	    rev = "08096e664aca5b59059de7f609bd9e0aaba95191";
	    sha256 = "07ld4zljg1mwr87zyk5myz8k24brr1lifndixz1y4hggwzzs41cq";
	  };

	  buildInputs = [ python3.pkgs.wrapPython ];
	  pythonPath = with python3.pkgs; [ requests flask gevent ];

	  installPhase = ''
	    sed -i '1i#!/usr/bin/env python' tvhProxy.py
	    install -D tvhProxy.py $out/bin/tvhproxy
            cp -rv templates $out/bin
	  '';

	  postFixup = "wrapPythonPrograms";
	  doCheck = false;

	};
	in {
	environment = {
	  TVH_URL = "http://tvheadend.lan:9981";
	  TVH_PROXY_URL = "http://localhost:5004";
          TVH_TUNER_COUNT = "1";
	};
	serviceConfig = {
	  ExecStart = "${tvh-proxy}/bin/tvhproxy";
	};
        wantedBy = [ "multi-user.target" ];
      };
    };
  };
}
