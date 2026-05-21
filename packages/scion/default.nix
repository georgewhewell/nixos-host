{
  lib,
  buildGoModule,
  fetchFromGitHub,
}: let
  rev = "9b4a9292a1806dadcfb1b6be9e6c4e7d8f34f51f";
  versionPkg = "github.com/GoogleCloudPlatform/scion/pkg/version";
  sciontoolPkg = "github.com/GoogleCloudPlatform/scion/cmd/sciontool/commands";
in
  buildGoModule rec {
    pname = "scion";
    version = "0-unstable-2026-05-08";

    src = fetchFromGitHub {
      owner = "GoogleCloudPlatform";
      repo = "scion";
      inherit rev;
      hash = "sha256-XE2yjOKCKQfWh2fT/l2Fe2UQuneqaYGL2JpzV9662is=";
    };

    vendorHash = "sha256-lgZ1ZD/ZGsxiszc5YGSWKhukF48ZLHkUJg1gpLJZzLs=";

    proxyVendor = true;

    subPackages = [
      "cmd/scion"
      "cmd/sciontool"
      "cmd/scion-broker-repl"
    ];

    # Skip embedding the web frontend (would require an npm/vite build).
    # Run `scion` with `--web-assets-dir` if you need the dashboard.
    tags = ["no_embed_web"];

    env.CGO_ENABLED = 0;

    ldflags = [
      "-s"
      "-w"
      "-X ${versionPkg}.Commit=${rev}"
      "-X ${versionPkg}.BuildTime=1970-01-01T00:00:00Z"
      "-X ${sciontoolPkg}.Commit=${rev}"
      "-X ${sciontoolPkg}.BuildTime=1970-01-01T00:00:00Z"
    ];

    # Tests reach for git, network, container runtimes, and a writable HOME.
    doCheck = false;

    meta = {
      description = "Multi-agent orchestration testbed for running deep agents in containers";
      homepage = "https://github.com/GoogleCloudPlatform/scion";
      license = lib.licenses.asl20;
      maintainers = [];
      mainProgram = "scion";
      platforms = lib.platforms.unix;
    };
  }
