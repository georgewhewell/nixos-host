{ pkgs ? import <nixpkgs> { } }:

pkgs.stdenv.mkDerivation {
  name = "webscreensaver";
  version = "0.1";

  src = pkgs.fetchFromGitHub {
    owner = "lmartinking";
    repo = "webscreensaver";
    rev = "05a736c00fb66d902269d492d1a07febb7c4ed95";
    sha256 = "0wq8lrial1khc0kv34g2n7wbl9bf9m3vfk29d51g6r0hg3vzp49l";
  };

  buildInputs = with pkgs; with python27Packages; [ gtk3 python gst-python pygtk pygobject3 pywebkitgtk webkitgtk ];
  propogatedBuildInputs = [ pkgs.python27 ];
  installPhase = ''
    mkdir -p $out/bin
    cp webscreensaver $out/bin/webscreensaver
  '';
  postInstall = ''
     wrapProgram "$out/bin/webscreensaver" \
    --prefix PYTHONPATH : "$PYTHONPATH" \
    --prefix GI_TYPELIB_PATH : "$GI_TYPELIB_PATH"
  '';
}
