{ config, pkgs, ... }:


{

  boot.kernelParams = [
    # https://gist.github.com/Brainiarc7/aa43570f512906e882ad6cdd835efe57
    "i915.enable_gvt=1"
    "i915.enable_fbc=1"
    "i915.enable_psr=1"
    "i915.disable_power_well=0"
    "i915.fastboot=1"
  ];

}
