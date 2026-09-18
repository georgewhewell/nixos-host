{ nanokvm }:
# SD-card image profile. Produces a flashable image with the vendor
# U-Boot + FIT layout the NanoKVM-PCIe carrier expects.
#
# Use case: actual deployment to the user's NanoKVM-PCIe device. Not
# used for USB-recovery development iterations — those go through
# the `usb-*` profiles instead.
{
  lib,
  rootAuthorizedKeys ? [],
  ...
}: {
  imports = [
    (nanokvm + "/modules/sg2002-vendor-fit.nix")
    (nanokvm + "/modules/sg2002-sd-image.nix")
  ];

  # The SD image is intended to chain-load via the vendor U-Boot
  # already on the SoC — override the platform default of "mainline".
  sg2002.uboot = lib.mkForce "vendor";
  sg2002.authorizedKeys = rootAuthorizedKeys;

  networking.hostName = lib.mkDefault "nanokvm";

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  users.users.root.initialPassword = "nixos";

  services.nanokvm = {
    enable = true;
    openFirewall = true;
  };

  # The vendor 5.10 SG2002 config lacks the
  # CONFIG_ARCH_MMAP_RND_*_MAX symbols nixpkgs' generic sysctl module
  # expects when generating this file.
  environment.etc."sysctl.d/55-nixos-aslr-entropy.conf".source = lib.mkForce (
    builtins.toFile "empty-aslr-entropy.conf" ""
  );

  environment.defaultPackages = lib.mkForce [];
  programs.nano.enable = lib.mkForce false;
  programs.less.enable = lib.mkForce false;
}
