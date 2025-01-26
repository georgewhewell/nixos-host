hardware: nixosModule: inputs:
with hardware; let
  inherit (inputs.nixpkgs) lib;
  sys = system: mods:
    lib.nixosSystem {
      inherit system;
      modules = [{_module.args = inputs;} nixosModule] ++ mods;
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs;
      };
    };
in {
  nixhost = sys "x86_64-linux" [physical ./x86/nixhost];
  router = sys "x86_64-linux" [physical ./x86/router];
  trex = sys "x86_64-linux" [physical ./x86/trex];

  rock-5b = sys "aarch64-linux" [physical ./aarch64/rock5b];
}
