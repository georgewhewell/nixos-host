{ go-ethereum, fetchFromGitHub }:

go-ethereum.overrideAttrs (o: {
  name = "optimism-geth";
  src = fetchFromGitHub {
    owner = "ethereum-optimism";
    repo = "optimism";
    rev = "master";
    sha256 = "sha256-guSvkH8CchQRrxLgY13/12n7MyMtO3/ckEinWN8Htkc=";
  };
})
