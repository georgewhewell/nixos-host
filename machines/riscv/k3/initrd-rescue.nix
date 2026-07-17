{
  inputs,
  ...
}: let
  sshKeys = import ../../../profiles/ssh-keys.nix;
in {
  imports = [
    inputs.nanokvm.nixosModules.boards.k3."pico-itx"."initrd-rescue"
  ];

  sconfig.profile = "server";
  spacemit.k3.authorizedKeys = builtins.attrValues sshKeys;
}
