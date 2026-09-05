{
  lib,
  buildGo127Module,
  fetchFromGitHub,
  stdenvNoCC,
  nodejs,
  pnpm_11,
  fetchPnpmDeps,
  pnpmConfigHook,
  typescript,
  versionCheckHook,
}:
buildGo127Module (finalAttrs: {
  pname = "qui";
  version = "1.27.0";

  src = fetchFromGitHub {
    owner = "autobrr";
    repo = "qui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-L8neWlBlPRDPaj8WTgw9h5kVbCg4ibOnVzXE8wzBFzw=";
  };

  qui-web = stdenvNoCC.mkDerivation (finalWebAttrs: {
    pname = "${finalAttrs.pname}-web";
    inherit (finalAttrs) src version;

    nativeBuildInputs = [
      nodejs
      pnpmConfigHook
      pnpm_11
      typescript
    ];

    sourceRoot = "${finalAttrs.src.name}/web";

    pnpmDeps = fetchPnpmDeps {
      inherit (finalWebAttrs)
        pname
        version
        src
        sourceRoot
        ;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      hash = "sha256-91ZOp0YHyB/ieR120kostIMa3SCql5X9mr8nNBMF9uc=";
    };

    postBuild = ''
      pnpm run build
    '';

    installPhase = ''
      cp -r dist $out
    '';
  });

  vendorHash = "sha256-IjBwsl4HY+9tV19hOt30Urk1Z8POLQZKFrcLQqd3VZg=";

  preBuild = ''
    cp -r ${finalAttrs.qui-web}/* web/dist
  '';

  ldflags = [
    "-X github.com/autobrr/qui/internal/buildinfo.Version=${finalAttrs.version}"
    "-X main.PolarOrgID="
  ];

  preCheck = ''
    export TMPDIR="$NIX_BUILD_TOP/test-tmp"
    mkdir -p "$TMPDIR"
  '';

  checkFlags = [ "-skip=TestRollback" ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "version";
  doInstallCheck = true;

  meta = {
    description = "Modern alternative webUI for qBittorrent, with multi-instance support";
    homepage = "https://github.com/autobrr/qui";
    changelog = "https://github.com/autobrr/qui/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl2Plus;
    mainProgram = "qui";
    platforms = lib.platforms.unix;
  };
})
