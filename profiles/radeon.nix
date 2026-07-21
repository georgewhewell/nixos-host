{ pkgs
, lib
, ...
}:
let
  rocmEnabled = pkgs.config.rocmSupport or false;
in
{

  hardware.amdgpu = {
    opencl.enable = lib.mkDefault rocmEnabled;
    overdrive = {
      enable = true;
      ppfeaturemask = "0xffffffff";
    };
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      libvdpau-va-gl
    ];
  };

  systemd.tmpfiles.rules = lib.optionals rocmEnabled [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  environment.systemPackages = with pkgs; [
    clinfo
    amdgpu_top
    radeontop
  ] ++ lib.optionals rocmEnabled [
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
    # libva-utils
  ];
}
