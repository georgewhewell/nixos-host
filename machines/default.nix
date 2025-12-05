nixosModule: inputs: mkSecret: let
  inherit (inputs.nixpkgs) lib;
  sys = system: machine:
    lib.nixosSystem {
      inherit system;
      modules = [
        {_module.args = inputs;}
        nixosModule
        machine
        inputs.disko.nixosModules.disko
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret;
      };
    };
in {
  router = sys "x86_64-linux" ./x86/router;
  trex = sys "x86_64-linux" ./x86/trex;
  n100 = sys "x86_64-linux" ./x86/n100;
  fuckup = sys "x86_64-linux" ./x86/fuckup;

  strix-1 = sys "x86_64-linux" (import ./x86/strix-halo 1);
  strix-2 = sys "x86_64-linux" (import ./x86/strix-halo 2);

  rock-5b = sys "aarch64-linux" ./aarch64/rock5b;
  prime = sys "aarch64-linux" ./aarch64/prime;
  neo2 = sys "aarch64-linux" ./aarch64/nanopi-neo2;
}
