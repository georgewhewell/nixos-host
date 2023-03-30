{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/ee01de29d2f58d56b1be4ae24c24bd91c5380cea;
    vpp.url = github:FDio/vpp/stable/2302;
    vpp.flake = false;
  };
  outputs = inputs@{ flake-parts, vpp, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        packages = {
          libmemif = pkgs.callPackage ./libmemif.nix {
            libmemifSource = vpp + "/extras/libmemif";
          };
          vpp = pkgs.callPackage ./vpp.nix {
            vppSource = vpp;
          };
        };
      };
    };
}
