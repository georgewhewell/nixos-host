{ config, lib, pkgs, boot, networking, containers, ... }:

{
  # systemd.services."container@jupyter" = {
  #   bindsTo = [ "mnt-var-lib-jupyter.mount" ];
  #   after = [ "mnt-var-lib-jupyter.mount" ];
  # };

  services.nginx.virtualHosts."jupyter.satanic.link" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
        proxyPass = "http://jupyter.lan:8789";
        proxyWebsockets = true;
    };
  };

  containers.jupyter = {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br0";

    bindMounts = {
      "/var/lib/jupyter" = {
        hostPath = "/mnt/Home/src/notebooks";
        isReadOnly = false;
      };
    };

    config = {
        imports = [ ../profiles/container.nix ];
        networking = {
            hostName = "jupyter";
            firewall = {
                allowedTCPPorts = [ 8789 ];
            };
        };

        services.jupyter = {
            enable = true;
            ip = "0.0.0.0";
            port = 8789;
            password = "'argon2:$argon2id$v=19$m=10240,t=10,p=8$UsB1OuBDVASPqoG/4VmWRw$9o0mYhY8fXIEMiQJf3CsoQ'";
            notebookConfig = ''
              c.NotebookApp.allow_origin = 'https://jupyter.satanic.link'
            '';
            kernels = {
                python3 = let
                    env = (pkgs.python3.withPackages (ps: with ps; [
                        ipykernel
                        jupyter
                        pandas
                        /* scikitlearn */
                        numpy
                        scipy
                        matplotlib

                        pytorch
                        tqdm
                    ]));
                in {
                    displayName = "Python 3";
                    argv = [
                        "${env.interpreter}"
                        "-m"
                        "ipykernel_launcher"
                        "-f"
                        "{connection_file}"
                    ];
                    language = "python";
                };


            };
        };
    };
  };

}
