colmena: nixpkgs: hardware: nixosModule:
with hardware;

let
  colmenaModule = { ... }: {
    environment.systemPackages = [ colmena.packages."x86_64-linux".colmena ];
  };
  sys = system: mods: nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [ nixosModule colmenaModule ] ++ mods;
    extraModules = [ colmena.nixosModules.deploymentOptions ];
  };
in
{
  fuckup = sys "x86_64-linux" [ physical ./x86/fuckup ];
  nixhost = sys "x86_64-linux" [ physical ./x86/nixhost ];
  yoga = sys "x86_64-linux" [ physical ./x86/yoga ];

  cloud = sys "x86_64-linux" [ physical ./x86/cloud ];
  ax101 = sys "x86_64-linux" [ physical ./x86/ax101 ];
}
