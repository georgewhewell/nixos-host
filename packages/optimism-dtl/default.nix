{ mkYarnPackage
, fetchFromGitHub
}:

let
  src = fetchFromGitHub {
    owner = "ethereum-optimism";
    repo = "optimism";
    rev = "master";
    sha256 = "sha256-RW3zdCSx3h3HqgjNg96JE72ezDmytSUiF6lGi87Z3G8=";
  };
in

rec {

  core-utils = mkYarnPackage {
    pname = "optimism-packages";
    version = "master";

    # inherit src;

    yarnLock = ./yarn.lock;
    src = "${src}/packages/core-utils";

    # installPhase = ''
    #   mkdir -p $out/bin
    #   cp packages/data-transport-layer $out/bin
    #   # wrapProgram "$out/bin/public-ip-sync-google-clouddns.sh" \
    #   #  --prefix PATH : "${dnsutils}/bin" \
    #   #  --prefix PATH : "${google-cloud-sdk}/bin" \
    #   #    --prefix PATH : "${curl}/bin"
    # '';

    # buildInputs = [ nodePackages.yarn ];
  };

  contracts = mkYarnPackage {
    pname = "optimism-packages";
    version = "master";

    # inherit src;

    yarnLock = ./yarn.lock;
    src = "${src}/packages/contracts";

    # installPhase = ''
    #   mkdir -p $out/bin
    #   cp packages/data-transport-layer $out/bin
    #   # wrapProgram "$out/bin/public-ip-sync-google-clouddns.sh" \
    #   #  --prefix PATH : "${dnsutils}/bin" \
    #   #  --prefix PATH : "${google-cloud-sdk}/bin" \
    #   #    --prefix PATH : "${curl}/bin"
    # '';

    buildInputs = [ core-utils ];
  };


  dtl = mkYarnPackage {
    pname = "optimism-packages";
    version = "master";

    # inherit src;

    yarnLock = ./yarn.lock;
    src = "${src}/packages/data-transport-layer";

    # installPhase = ''
    #   mkdir -p $out/bin
    #   cp packages/data-transport-layer $out/bin
    #   # wrapProgram "$out/bin/public-ip-sync-google-clouddns.sh" \
    #   #  --prefix PATH : "${dnsutils}/bin" \
    #   #  --prefix PATH : "${google-cloud-sdk}/bin" \
    #   #    --prefix PATH : "${curl}/bin"
    # '';

    # buildInputs = [ nodePackages.yarn ];
  };
}

