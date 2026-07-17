{ disk1 ? null
, disk2 ? null
, espSize ? "4G"
, specialSize ? "64G"
, ...
}:
let
  optionalAttrs = condition: attrs:
    if condition then attrs else { };

  mkDisk = name: vfatLabel: device: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          label = "trex-${name}-ESP";
          size = espSize;
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = [ "-F" "32" "-n" vfatLabel ];
          };
        };
        special = {
          label = "trex-${name}-bpool-special";
          size = specialSize;
          type = "BF01";
        };
        l2arc = {
          label = "trex-${name}-bpool-l2arc";
          size = "100%";
          type = "BF01";
        };
      };
    };
  };
in
assert disk1 != null || disk2 != null;
{
  disko.devices = {
    disk =
      optionalAttrs (disk1 != null)
        {
          trex-boot-a = mkDisk "boot-a" "TREXBOOTA" disk1;
        }
      // optionalAttrs (disk2 != null) {
        trex-boot-b = mkDisk "boot-b" "TREXBOOTB" disk2;
      };
  };
}
