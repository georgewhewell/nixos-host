with (import <nixpkgs> { });

stdenv.mkDerivation {
  name = "nixfiles-terraform";
  buildInputs = [
    (terraform.withPlugins (p: [
      p.google
      p.google-beta
      p.aws
      p.kubernetes
    ]))
    kubectl
    google-cloud-sdk
  ];

  GOOGLE_APPLICATION_CREDENTIALS = "../../secrets/nixos-secrets/domain-owner-terraformer.json";

}
