{...}: {
  documentation.enable = false;
  documentation.nixos.enable = false;

  services.udisks2.enable = false;
  services.polkit.enable = false;
}
