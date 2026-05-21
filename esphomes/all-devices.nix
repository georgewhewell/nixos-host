{pkgs}: let
  libModule = import ./lib.nix {inherit pkgs;};
  inherit (libModule) lib yamlFormat evalNamedDevice;

  devicesDir = ./devices;

  deviceNames = let
    entries = builtins.readDir devicesDir;
  in
    builtins.sort builtins.lessThan (
      lib.mapAttrsToList (n: _: lib.removeSuffix ".nix" n) (
        lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) entries
      )
    );

  renderOne = name: let
    evaled = evalNamedDevice {inherit name;};
    failed = builtins.filter (a: !a.assertion) evaled.config.assertions;
  in
    if failed != []
    then
      throw (
        "ESPHome module assertions failed for ${name}:\n"
        + lib.concatStringsSep "\n" (map (a: "- ${a.message}") failed)
      )
    else {
      inherit name;
      yaml = yamlFormat.generate "${name}.yaml" evaled.config.esphome.settings;
      requiredSubstitutions = lib.unique evaled.config.esphome.requiredSubstitutions;
    };

  devices = map renderOne deviceNames;

  allRequiredSubstitutions =
    lib.unique (lib.concatMap (d: d.requiredSubstitutions) devices);

  yamlDir = pkgs.runCommand "esphome-yamls" {} (
    "mkdir -p $out\n"
    + lib.concatMapStringsSep "\n"
    (d: "cp ${d.yaml} $out/${d.name}.yaml")
    devices
  );
in {
  inherit deviceNames devices allRequiredSubstitutions yamlDir;
}
