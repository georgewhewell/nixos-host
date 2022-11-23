{ config, lib, ... }:
let
  cfg = config.sconfig.scroll-boost;
in
{
  options.sconfig.scroll-boost = lib.mkEnableOption "Patch xf86-libinput scroll speed";

  config = lib.mkIf cfg {
    nixpkgs.overlays = [
      (self: super: {
        xorg = super.xorg.overrideScope' (selfB: superB: {
          inherit (super.xorg) xlibsWrapper;
          xf86inputlibinput = superB.xf86inputlibinput.overrideAttrs (attr: {
            patches = [ ./libinput.patch ];
          });
        });
      })
    ];
  };
}
