self: super:

{
  # Append local packages
} // (import ../packages { pkgs = super; })
