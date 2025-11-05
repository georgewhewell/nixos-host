{
  lib,
  pkgs,
  ...
}: {
  # hardware.enableAllFirmware = true;
  # deployment.keys."wifi-psk" = {
  #   keyCommand = ["pass" "VM4588425"];
  #   destDir = "/run/secrets";
  #   user = "root";
  #   group = "root";
  #   permissions = "0400";
  # };

  # networking.wireless = {
  #   enable = lib.mkDefault true;
  #   environmentFile = "/run/secrets/wifi-psk";
  #   networks = {
  #     VM4588425 = {
  #       pskRawPath = "@VM4588425_PSK@";
  #     };
  #   };
  # };

  # systemd.services.wpa_supplicant.wantedBy = pkgs.lib.mkForce ["multi-user.target"];
  # systemd.services.wpa_supplicant = {
  #   startLimitIntervalSec = 5;
  #   startLimitBurst = 1;
  #   serviceConfig = {
  #     Restart = "on-failure";
  #     RestartSec = "1";
  #   };
  # };
}
