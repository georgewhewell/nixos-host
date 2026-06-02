# Common Nix settings for all systems (NixOS and Darwin)
{ lib, network, ... }: {
  nix = {
    optimise.automatic = lib.mkDefault true;

    settings = {
      trusted-users = [ "grw" ];
      extra-substituters = [
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "${network.publicFqdn "trex"}:MNNZXj1HAgh1+9465A8qWnZ8VR67a++lhvCIrjSK03Q="
        "colmena.cachix.org-1:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      build-users-group = lib.mkDefault "nixbld";
      experimental-features = [ "nix-command" "flakes" ];

      # Reasonable defaults (https://jackson.dev/post/nix-reasonable-defaults/)
      connect-timeout = 5;
      min-free = 128000000; # 128 MB
      max-free = 1000000000; # 1 GB
      fallback = true;
      warn-dirty = false;
      auto-optimise-store = true;
    };
  };
}
