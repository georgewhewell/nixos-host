with (import <nixpkgs> { });

stdenv.mkDerivation {
   name = "nixfiles-terraform";
   buildInputs = [
    (terraform.withPlugins (p: [
      p.google p.google-beta
    ]))
    kubectl
    google-cloud-sdk
  ];

  GOOGLE_APPLICATION_CREDENTIALS = "../secrets/domain-owner-terraformer.json";
}
