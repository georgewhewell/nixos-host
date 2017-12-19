self: super:

{
  bitcoin = super.bitcoin.overrideAttrs (old: {
    buildInputs = old.buildInputs ++ [ super.zmq ];
    configureFlags = old.configureFlags ++ [ "--with-zmq" ];
  });

  libfprint = super.libfprint.overrideAttrs (old: {
    src = super.fetchFromGithub {
      owner = "nmikhailov";
      repo = "Validity90";
      rev = "00ac6ab7f54b012a8a0627fb389bd62ebf14c4fb";
      sha256 = "0wq8lrial1khc0kv34g2n7wbl9bf9m3vfk29d51g6r0hg3vzp49l";
    };
  });
}
