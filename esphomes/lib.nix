{pkgs}: let
  lib = pkgs.lib;
  yamlFormat = pkgs.formats.yaml {};
in rec {
  inherit lib pkgs yamlFormat;

  evalDevice = {
    deviceModule,
    extraModules ? [],
    specialArgs ? {},
  }:
    lib.evalModules {
      inherit specialArgs;
      modules =
        [
          {
            options.assertions = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule ({...}: {
                  options = {
                    assertion = lib.mkOption {
                      type = lib.types.bool;
                    };
                    message = lib.mkOption {
                      type = lib.types.str;
                    };
                  };
                })
              );
              default = [];
              description = "Module assertions checked by the ESPHome wrapper entrypoints.";
            };

            options.esphome = {
              # Freeform ESPHome YAML tree. We only declare this single option so
              # nested keys get recursive merging semantics from the YAML type.
              settings = lib.mkOption {
                type = yamlFormat.type;
                default = {};
                description = "Rendered ESPHome YAML configuration.";
              };

              # Runtime substitutions expected by the wrapper (passed to
              # `esphome -s key value`). Shared modules can append to this.
              requiredSubstitutions = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Required runtime ESPHome substitutions.";
              };

              # How to resolve substitutions when no ESPHOME_SUBST_<key> env var
              # is provided. This keeps secret resolution out of the Nix store.
              substitutionSources = lib.mkOption {
                type = lib.types.attrsOf (
                  lib.types.submodule ({...}: {
                    options = {
                      type = lib.mkOption {
                        type = lib.types.enum ["sops-yaml"];
                        description = "Runtime substitution source type.";
                      };
                      file = lib.mkOption {
                        type = lib.types.str;
                        description = "Repo-relative or absolute path to secret file.";
                      };
                      key = lib.mkOption {
                        type = lib.types.str;
                        description = "Top-level YAML key to extract.";
                      };
                    };
                  })
                );
                default = {};
                description = "Substitution source bindings for the wrapper.";
              };
            };

            config._module.args = {
              inherit lib pkgs;
            };
          }
          # Auto-populate a `substitutions:` block with sentinel values for
          # every required substitution. This makes rendered YAML valid
          # standalone (e.g. for the ESPHome dashboard). The sentinel form
          # "@@SECRET:KEY@@" is rewritten to `!secret KEY` at service start,
          # and is harmlessly overridden by `esphome -s KEY VALUE` on the CLI.
          ({config, ...}: {
            config.esphome.settings.substitutions =
              lib.genAttrs config.esphome.requiredSubstitutions
              (k: "@@SECRET:${k}@@");
          })
          deviceModule
        ]
        ++ extraModules;
    };

  evalNamedDevice = {
    name,
    extraModules ? [],
    specialArgs ? {},
  }: let
    deviceModule = ./devices + "/${name}.nix";
  in
    evalDevice {
      inherit deviceModule extraModules specialArgs;
    };
}
