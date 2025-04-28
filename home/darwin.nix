{pkgs, ...}: {
  # replace crappy mac utils
  home.packages = with pkgs; [
    gnused
    coreutils
  ];
}
