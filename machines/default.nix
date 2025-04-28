nixosModule: inputs: let
  inherit (inputs.nixpkgs) lib;
  sys = system: machine:
    lib.nixosSystem {
      inherit system;
      modules = [{_module.args = inputs;} nixosModule machine];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs;
      };
    };
in {
  nixhost = sys "x86_64-linux" ./x86/nixhost;
  router = sys "x86_64-linux" ./x86/router;
  trex = sys "x86_64-linux" ./x86/trex;
  n100 = sys "x86_64-linux" ./x86/n100;
  rock-5b = sys "aarch64-linux" ./aarch64/rock5b;
}
