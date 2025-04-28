# NixOS Configuration Guidelines

## Build & Deploy Commands
- Build all: `nix flake check`
- Build specific host: `nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel`
- Deploy with Colmena: `colmena apply`
- Deploy single host: `colmena apply --on <hostname>`
- Test changes: `colmena build`
- Development shell: `nix develop`

## Style Guidelines
- Attribute set formatting: `{ pkgs, config, lib, ... }: { ... }`
- Import organization: Place imports at top of file
- Use `lib.mkDefault` for overridable values, `lib.mkForce` for mandatory values
- Indent with two spaces for all Nix files
- Use attribute sets for complex options instead of positional arguments
- File naming: Use descriptive names (common.nix, desktop.nix) matching functionality

## Project Structure
- `/home/`: Home Manager configurations
- `/machines/`: Per-machine configurations
- `/modules/`: Reusable NixOS modules
- `/profiles/`: Common functionality groups
- `/services/`: Service-specific configurations
- `/overlays/`: Package customizations

## Best Practices
- Make code modular through imports
- Prefer profile imports over direct configuration
- Use Home Manager for user environment
- Leverage flakes for reproducible builds
- Use `specialArgs` to pass required context
- Test changes with `colmena build` before deploying