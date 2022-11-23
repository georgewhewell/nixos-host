{ lib, ... }:
with lib.types;
{
  options.sconfig = {

    sshPublicKeys = lib.mkOption {
      type = listOf str;
      default = [ ];
    };

    deployment = lib.mkOption {
      type = attrs;
      default = { };
    };

  };
}
