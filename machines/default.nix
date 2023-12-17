colmena: nixpkgs: hardware: nixosModule: apple-silicon:

with hardware;

let
  sys = system: mods: nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ nixosModule ] ++ mods;
    extraModules = [ colmena.nixosModules.deploymentOptions ];
  };
  applesys = apple-silicon: system: mods: nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      nixosModule
      apple-silicon.nixosModules.default
    ] ++ mods;
    extraModules = [
      colmena.nixosModules.deploymentOptions
    ];
  };
in
{
  fuckup = sys "x86_64-linux" [ physical ./x86/fuckup ];
  nixhost = sys "x86_64-linux" [ physical ./x86/nixhost ];
  # yoga = sys "x86_64-linux" [ physical ./x86/yoga ];
  router = sys "x86_64-linux" [ physical ./x86/router ];

  cloud = sys "x86_64-linux" [ physical ./x86/cloud ];

  rock-5b = sys "aarch64-linux" [ physical ./aarch64/rock5b ];
  air = applesys apple-silicon "aarch64-linux" [ physical ./aarch64/air ];

}
