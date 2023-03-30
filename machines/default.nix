colmena: nixpkgs: hardware: nixosModule: rock5b:
with hardware;

let
  sys = system: mods: nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ nixosModule ] ++ mods;
    extraModules = [ colmena.nixosModules.deploymentOptions ];
  };
  rocksys = rock5b: system: mods: nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ nixosModule rock5b.nixosModules.kernel ] ++ mods;
    extraModules = [ colmena.nixosModules.deploymentOptions ];
  };
in
{
  fuckup = sys "x86_64-linux" [ physical ./x86/fuckup ];
  nixhost = sys "x86_64-linux" [ physical ./x86/nixhost ];
  yoga = sys "x86_64-linux" [ physical ./x86/yoga ];
  router = sys "x86_64-linux" [ physical ./x86/router ];

  cloud = sys "x86_64-linux" [ physical ./x86/cloud ];
  ax101 = sys "x86_64-linux" [ physical ./x86/ax101 ];

  rock5b = rocksys rock5b "aarch64-linux" [ physical ./aarch64/rock5b ];
  air = sys "aarch64-linux" [ physical ./aarch64/air ];

}
