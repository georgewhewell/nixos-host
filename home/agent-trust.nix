{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.programs.agentDirectoryTrust;

  # Every coding agent's directory-trust store keys on the exact absolute
  # path the tool was launched in -- Codex, Claude Code and Grok Build all
  # confirmed to have NO ancestor/parent trust (openai/codex#14547 and
  # xAI's own trusted_folders.toml behaviour: trusting "/mnt/Home/src" does
  # not cover "/mnt/Home/src/foo"), and Codex additionally confirmed to have
  # no glob/wildcard support at all (`[projects."*"]` is documented as
  # inert -- https://codexinsider.com/config/projects-trust-level/, echoed
  # in openai/codex#14547). So every real project directory needs its own
  # entry.
  #
  # PURE evaluation, by design: `paths` is plain list concatenation, no
  # filesystem access, so `nix eval`/`colmena build`/`colmena apply` need
  # no `--impure` for any host with
  # `sconfig.home-manager.enableDevelopment = true`. The trade-off is that
  # a new project directory is NOT picked up automatically -- add it to
  # `projects` (or `extraPaths`) below and rebuild. An earlier version of
  # this module used `builtins.readDir` to auto-discover every directory
  # under a root; that traded purity for auto-discovery and also
  # auto-trusted ~1300 ephemeral scratch/worktree checkouts alongside the
  # ~20 real project roots. Deliberately reverted: roots + a curated list
  # only.
  paths = lib.unique (cfg.roots ++ cfg.projects ++ cfg.extraPaths);

  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.agentDirectoryTrust = {
    enable = lib.mkEnableOption "declarative directory trust for AI coding agents (Codex, Claude Code, Grok Build, Antigravity/Gemini, opencode)";

    roots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/mnt/Home/src" ];
      description = ''
        Trusted project-tree roots. Consumed two ways: as exact-path
        entries in `paths` (below) for tools with no ancestor trust, and
        as glob prefixes ("''${root}/**") for tools that do support globs
        (currently just opencode's `external_directory` permission).
        Adding a directory here does NOT by itself trust every checkout
        under it for Codex/Claude/Grok/Antigravity -- see `projects`.
      '';
      example = [ "/mnt/Home/src" ];
    };

    projects = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/mnt/Home/src"
        "/mnt/Home/src/amd-strix-halo-vllm-toolboxes"
        "/mnt/Home/src/ax35b-ec-dump"
        "/mnt/Home/src/blog"
        "/mnt/Home/src/btop"
        "/mnt/Home/src/explorer"
        "/mnt/Home/src/hellas"
        "/mnt/Home/src/hellas-agents"
        "/mnt/Home/src/hellas-ai-video"
        "/mnt/Home/src/hellas-alto"
        "/mnt/Home/src/hellas-esp32"
        "/mnt/Home/src/hellas-extras/hellas-esp32"
        "/mnt/Home/src/hellasbox"
        "/mnt/Home/src/infra"
        "/mnt/Home/src/nix-evals"
        "/mnt/Home/src/nix-strix-halo"
        "/mnt/Home/src/nixos-config"
        "/mnt/Home/src/nixos-gemini"
        "/mnt/Home/src/nixos-nanokvm"
        "/mnt/Home/src/node"
        "/mnt/Home/src/strix-inf"
        "/mnt/Home/src/thunderbolt-ibverbs"
        "/mnt/Home/src/thunderbolt-ibverbs-kernel-clean"
      ];
      description = ''
        The curated, hand-maintained list of real (non-ephemeral) project
        directories to pre-trust for every exact-path-only agent. This is
        THE one place to add a new project: append its path here and
        rebuild. Recovered verbatim from the `agentTrustedDirs` list this
        module replaces (commit c5d3da5) -- deliberately NOT
        auto-generated from the filesystem, so it never sweeps in scratch
        or worktree checkouts.
      '';
      example = [ "/mnt/Home/src/some-new-project" ];
    };

    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Individual extra paths to pre-trust that live outside `roots`
        entirely (e.g. /home/grw/src/*, /tmp checkouts). Prefer `projects`
        for anything under a root -- this list is for genuine one-offs.
      '';
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = paths;
      description = ''
        Computed (roots ++ projects ++ extraPaths), deduplicated. This is
        what Codex/Claude/Grok/Antigravity actually consume as exact-path
        trust entries; opencode instead consumes `roots` as glob prefixes
        (cheaper coverage, see where it is wired up).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Grok Build: ~/.grok/trusted_folders.toml [folders."<path>"] trusted.
    # Exact-path only (no glob/ancestor trust found in xAI's docs or the
    # live trust store on this box -- every sibling checkout carries its
    # own entry). The live file holds nothing but trust records (no other
    # tool-owned state coexists in it), so it is safe to fully own as a
    # real Nix-store-generated file: no activation script, no merge, no
    # mutable state to clobber. If Grok is ever launched somewhere outside
    # `paths` and the interactive trust dialog tries to persist a new
    # decision, that write will fail against the read-only store symlink --
    # the same failure class Codex's config.toml had (and, deliberately,
    # keeps not having -- see development.nix's codex activation). Add the
    # directory to `projects`/`extraPaths` and rebuild instead of trusting
    # it interactively.
    home.file.".grok/trusted_folders.toml".source = tomlFormat.generate "trusted_folders.toml" {
      folders = lib.genAttrs paths (_: { trusted = true; });
    };

    # --- Claude Code: ~/.claude.json .projects[path].hasTrustDialogAccepted.
    # The ONE genuine exception in this module: ~/.claude.json is Claude
    # Code's live conversation/session/usage-history state, rewritten
    # constantly by the tool itself (61KB+ and growing on this box). Making
    # it a Nix-store symlink would not just risk losing a trust decision --
    # it would break the tool outright (it needs to append/rewrite this
    # file every session). Checked the installed claude-code 2.1.270
    # binary directly (`strings` over `.claude-wrapped`) for a
    # managed-settings.json / settings.json / env-var alternative: none
    # exists. Every code path that grants trust
    # (`checkHasTrustDialogAccepted`, `getHomeTrustDialogAccepted`,
    # `setHomeTrustDialogAccepted`) reads/writes exactly
    # `projects[path].hasTrustDialogAccepted` in `~/.claude.json`, and the
    # tool's own error text confirms it: "...accept the trust dialog here
    # once interactively, or set projects[<path>].hasTrustDialogAccepted
    # in ~/.claude.json". So this one file keeps a minimal activation merge
    # -- only touching the trust key, never replacing the file.
    home.activation.claudeDirectoryTrust = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      claude_json="$HOME/.claude.json"
      if [ -s "$claude_json" ] && ${pkgs.jq}/bin/jq -e 'type == "object"' "$claude_json" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq --argjson paths '${builtins.toJSON paths}' '
          .projects = (.projects // {}) |
          reduce $paths[] as $p (.;
            .projects[$p] = ((.projects[$p] // {}) + { hasTrustDialogAccepted: true })
          )
        ' "$claude_json" > "$claude_json.new" 2>/dev/null \
          && ${pkgs.coreutils}/bin/chmod --reference="$claude_json" "$claude_json.new" 2>/dev/null \
          && ${pkgs.coreutils}/bin/mv "$claude_json.new" "$claude_json" \
          || { ${pkgs.coreutils}/bin/rm -f "$claude_json.new"; echo "claude: ~/.claude.json trust merge failed, left the file untouched" >&2; }
      else
        echo "claude: ~/.claude.json missing or not a JSON object, skipping trust seeding" >&2
      fi
    '';

    # --- Antigravity (the actually-installed "Gemini" tool; nix-ai-tools'
    # antigravity-cli, the successor to the deprecated gemini-cli) ---
    #
    # The prior implementation targeted ~/.gemini/trustedFolders.json with
    # a "TRUST_FOLDER" value and ~/.gemini/settings.json
    # security.folderTrust.enabled. That is the *upstream gemini-cli* (JS)
    # schema, documented in google-gemini/gemini-cli#13125 -- but
    # gemini-cli isn't packaged here at all (deprecated per the comment a
    # few hundred lines down in this file's sibling development.nix), and
    # antigravity-cli is a from-scratch Go rewrite. Verified directly:
    # `strings` over the installed antigravity-cli 1.2.2 binary
    # (`/nix/store/.../antigravity-cli-1.2.2/bin/agy`) contains zero
    # occurrences of "TRUST_FOLDER", "TRUST_PARENT", or "trustedFolders" in
    # any form, so that file/key is dead weight for the tool actually in
    # use. What the binary does contain -- and what the live file on this
    # box already has real, accumulated entries in -- is
    # `~/.gemini/antigravity-cli/settings.json`'s `.trustedWorkspaces`
    # array (a flat list of exact paths; the live file lists
    # "/mnt/Home/src" AND several of its children side by side, so this
    # does NOT cascade to subdirectories either -- exact-path enumeration
    # applies here too).
    #
    # That settings.json is a second genuine exception, not a clean
    # declarative target: alongside trust it already carries `model` and
    # an interactively-accumulated `permissions.allow` command allowlist
    # that the tool itself writes. A Nix-store symlink would risk losing
    # both on the next approval, so this merges only `.trustedWorkspaces`
    # and leaves everything else in the file untouched.
    home.activation.antigravityDirectoryTrust = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      antigravity_dir="$HOME/.gemini/antigravity-cli"
      ${pkgs.coreutils}/bin/mkdir -p "$antigravity_dir"
      antigravity_settings="$antigravity_dir/settings.json"
      [ -s "$antigravity_settings" ] || echo '{}' > "$antigravity_settings"
      if ${pkgs.jq}/bin/jq -e 'type == "object"' "$antigravity_settings" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq --argjson paths '${builtins.toJSON paths}' '
          .trustedWorkspaces = (((.trustedWorkspaces // []) + $paths) | unique)
        ' "$antigravity_settings" > "$antigravity_settings.new" 2>/dev/null \
          && ${pkgs.coreutils}/bin/chmod --reference="$antigravity_settings" "$antigravity_settings.new" 2>/dev/null \
          && ${pkgs.coreutils}/bin/mv "$antigravity_settings.new" "$antigravity_settings" \
          || { ${pkgs.coreutils}/bin/rm -f "$antigravity_settings.new"; echo "antigravity: settings.json trust merge failed, left the file untouched" >&2; }
      else
        echo "antigravity: ~/.gemini/antigravity-cli/settings.json is not a JSON object, skipping trust seeding" >&2
      fi
    '';
  };
}
