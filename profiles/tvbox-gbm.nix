{ config, pkgs, lib, ... }:

let
  kodiWithAddons = { lib, kodiPackages, makeWrapper, buildEnv, kodi, addons, callPackage }:
    let

      # linux distros are supposed to provide pillow and pycryptodome
      requiredPythonPath = with kodi.pythonPackages; makePythonPath ([ pillow pycryptodome ]);

      # each kodi addon can potentially export a python module which should be included in PYTHONPATH
      # see any addon which supplies `passthru.pythonPath` and the corresponding entry in the addons `addon.xml`
      # eg. `<extension point="xbmc.python.module" library="lib" />` -> pythonPath = "lib";
      additionalPythonPath =
        let
          addonsWithPythonPath = lib.filter (addon: addon ? pythonPath) addons;
        in
        lib.concatMapStringsSep ":" (addon: "${addon}${kodiPackages.addonDir}/${addon.namespace}/${addon.pythonPath}") addonsWithPythonPath;
    in

    buildEnv {
      name = "${kodi.name}-env";

      paths = [ kodi ] ++ addons;
      pathsToLink = [ "/share" ];

      nativeBuildInputs = [ makeWrapper ];

      postBuild = ''
        mkdir $out/bin
        for exe in kodi{,-standalone}
        do
          makeWrapper ${kodi}/bin/$exe $out/bin/$exe \
            --prefix PYTHONPATH : ${requiredPythonPath}:${additionalPythonPath} \
            --prefix KODI_HOME : $out/share/kodi \
            --prefix LD_LIBRARY_PATH ":" "${lib.makeLibraryPath
              (lib.concatMap
                (plugin: plugin.extraRuntimeDependencies or []) addons)}"
        done
      '';
    };
in
{

  sound.enable = true;

  # dont need this- interferes with kodi
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  security.polkit.enable = true;
  services.upower.enable = true;

  boot.plymouth.enable = false;

  users.extraUsers.kodi = {
    isNormalUser = true;
    uid = 1002;
    extraGroups = [ "audio" "video" "input" ];
  };

  systemd.services.kodi-gbm =
    let
      kodi = kodiWithAddons {
        inherit (pkgs) lib makeWrapper buildEnv callPackage kodiPackages;
        kodi = pkgs.kodi-rock5b;
        addons = with pkgs.kodiPackages; [
          youtube
          jellyfin
          pvr-iptvsimple
        ];
      };
    in
    {
      wants = [ "network-online.target" "polkit.service" ];
      conflicts = [ "getty@tty1.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        PAN_MESA_DEBUG = "gofaster";
      };
      serviceConfig = {
        ExecStart = "${kodi}/bin/kodi --standalone";
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty1";
        PAMName = "login";
        User = "kodi";
      };
    };

  services.avahi.enable = true;

  networking.firewall.allowedTCPPorts = [ 8080 ];

  environment.systemPackages = with pkgs; [
    libva1
    libva-utils
    glxinfo
    kmscube
    strace
  ];

}
