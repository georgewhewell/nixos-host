# Nix-to-ESPHome prototype

This is a small prototype for defining ESPHome devices with Nix modules and
rendering YAML for the ESPHome CLI.

Goals:

- Use Nix module merging (`imports`, `mkMerge`, `mkForce`, list concatenation)
  instead of YAML `!include` / `<<` merge behavior.
- Avoid `!secret` by using ESPHome substitutions and passing secret values at
  runtime with `esphome -s key value`.
- Keep secrets out of the Nix store (rendered YAML contains placeholders like
  `${wifi_password}`, not secret values).

## Layout

- `default.nix`: root entrypoint for the ESPHome Nix helpers
- `lib.nix`: module evaluation helpers + YAML renderer
- `modules/*.nix`: shared ESPHome fragments (translated from YAML includes)
- `devices/*.nix`: per-device configs (Nix module style)
- `external-components/`: minimal local ESPHome components still needed for
  the ESP32-P4 MIPI camera path
- `render-device.nix`: returns a generated YAML file derivation for a device
- `device-meta.nix`: returns metadata (currently required substitutions)
- `nix-to-esphome`: wrapper to render and invoke ESPHome

## Usage

Render YAML to stdout:

```bash
esphomes/nix-esphome render esp32-s3-amoled
```

Run ESPHome with substitutions:

```bash
esphomes/nix-esphome config esp32-s3-amoled
esphomes/nix-esphome compile esp32-s3-amoled
esphomes/nix-esphome run esp32-s3-amoled
```

If a device/module declares `esphome.substitutionSources`, the wrapper resolves
missing `ESPHOME_SUBST_*` values from SOPS automatically (using `sops --extract`).
Environment variables still override secret sources.

Example override:

```bash
export ESPHOME_SUBST_wifi_ssid='test-ssid'
esphomes/nix-esphome config esp32-s3-amoled
```

## Current limitation

This prototype uses native Nix YAML rendering (`pkgs.formats.yaml`). That works
well for plain YAML and substitutions, but not ESPHome YAML tags like `!lambda`
or `!secret`. `!secret` is intentionally replaced with substitutions. `!lambda`
still needs a later escape hatch (tagged value renderer or post-processor).
