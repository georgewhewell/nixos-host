{lib, ...}: {
  services.xserver.enable = false;
  services.displayManager.enable = false;
  hardware.graphics.enable = lib.mkDefault false;

  # Disable PipeWire/PulseAudio
  services.pipewire.enable = false;
  services.pulseaudio.enable = false;

  hardware.alsa.enable = lib.mkDefault false;
  hardware.bluetooth.enable = lib.mkDefault false;

  fonts.fontconfig.enable = false;

  documentation.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;

  services.udisks2.enable = lib.mkDefault false;
  services.accounts-daemon.enable = false;
  services.gnome.gnome-keyring.enable = false;
  security.polkit.enable = lib.mkDefault false; # if you don't need it
  programs.command-not-found.enable = false;

  programs.nano.enable = false;
  environment.defaultPackages = []; # removes perl, rsync, strace

  networking.networkmanager.enable = lib.mkDefault false; # use systemd-networkd instead
  networking.modemmanager.enable = false;

  console.font = lib.mkOverride 900 null;

  # services.avahi.enable = lib.mkForce false;

  # Disable nixos-rebuild and installer tools - managed remotely via colmena
  system.disableInstallerTools = true;
}
