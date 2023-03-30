# VPP nix flake

This flake provides the VPP package from https://wiki.fd.io/view/VPP

## Building

In order to build the standard flake, run:

```sh
$ nix build github:tfc/vpp-flake
```

This repo does not need to be checked out for this.

The build can be omitted by using cachix with the cache that is used by this
repo's CI:

```sh
# run this before doing the build step
$ cachix use tfc
```
