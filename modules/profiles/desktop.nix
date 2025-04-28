{
  config,
  lib,
  ...
}:
with lib; {
  config = mkIf (config.sconfig.profile == "desktop") {
    sconfig = {
      # security-tools = true;
    };

    environment.variables.MOZ_ENABLE_WAYLAND = "1";
    environment.variables.MOZ_USE_XINPUT2 = "1";

    # Disable suspend and hibernation
    services.logind.extraConfig = ''
      HandleSuspendKey=ignore
      HandleLidSwitch=ignore
      HandleLidSwitchExternalPower=ignore
      HandleLidSwitchDocked=ignore
      HandleHibernateKey=ignore
      HandlePowerKey=ignore
    '';

    # Disable automatic powering off
    systemd.services.systemd-logind.environment.LOGIND_AUTO_SUSPEND = "no";

    # Disable systemd's suspend, hibernate and hybrid-sleep units
    systemd.services = {
      "systemd-suspend.service".enable = false;
      "systemd-hibernate.service".enable = false;
      "systemd-hybrid-sleep.service".enable = false;
    };
  };
}
