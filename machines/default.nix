colmena: nixpkgs: hardware: nixosModule: inputs: consts:

with hardware;

let
  sys = system: mods: nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [{ _module.args = inputs; } nixosModule] ++ mods;
    extraModules = [ colmena.nixosModules.deploymentOptions ];
    specialArgs = { inherit inputs; inherit consts; };
  };
in
{
  nixhost = sys "x86_64-linux" [ physical ./x86/nixhost ];
  router = sys "x86_64-linux" [ physical ./x86/router ];
  trex = sys "x86_64-linux" [ physical ./x86/trex ];
  cloud = sys "x86_64-linux" [ physical ./x86/cloud ];

  # rock-5b = sys "aarch64-linux" [ physical ./aarch64/rock5b ];
  # air = sys "aarch64-linux" [ physical ./aarch64/air ];

}
