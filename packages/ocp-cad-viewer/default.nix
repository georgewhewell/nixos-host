{
  lib,
  buildFHSEnv,
  writeShellScript,
  uv,
  python312,
}:
# OCP CAD Viewer (https://github.com/bernhard-42/vscode-ocp-cad-viewer) python
# backend. The OCP/OpenCascade stack is impractical to build from source in
# nixpkgs (cq-flake is stale against current nixpkgs), so we run the upstream
# manylinux wheels — which bundle OpenCascade — inside an FHS sandbox via uv.
#
# Usage:
#   ocp-cad-viewer          # bootstrap venv (build123d, cadquery, ocp_vscode) and drop into a shell
#   ocp-cad-viewer serve    # run the standalone viewer server on http://127.0.0.1:3939
#   ocp-cad-viewer python … # run python with the venv active
#
# The venv lives at $XDG_DATA_HOME/ocp-cad-viewer (default ~/.local/share/...).
# Point the VS Code OCP CAD Viewer extension at that venv's bin/python.
let
  bootstrap = writeShellScript "ocp-cad-viewer-bootstrap" ''
    set -euo pipefail
    venv="''${XDG_DATA_HOME:-$HOME/.local/share}/ocp-cad-viewer/venv"
    if [ ! -x "$venv/bin/python" ]; then
      echo "ocp-cad-viewer: creating venv at $venv (first run)…" >&2
      uv venv --python ${python312}/bin/python3.12 "$venv"
      # build123d + ocp_vscode resolve to a consistent cadquery-ocp (OCCT 7.9).
      # Do NOT add the stable `cadquery` package here: it pins an older
      # cadquery-ocp (OCCT 7.8) and forces uv to backtrack build123d to a
      # version whose TopoDS API mismatches, breaking imports. Extra packages
      # can be added via $OCP_CAD_VIEWER_EXTRA_PIP (space-separated).
      VIRTUAL_ENV="$venv" uv pip install --python "$venv/bin/python" \
        build123d ocp_vscode ''${OCP_CAD_VIEWER_EXTRA_PIP:-}
    fi
    export VIRTUAL_ENV="$venv"
    export PATH="$venv/bin:$PATH"
    case "''${1:-}" in
      serve) shift; exec python -m ocp_vscode "$@" ;;
      "")    exec bash ;;
      *)     exec "$@" ;;
    esac
  '';
in
buildFHSEnv {
  name = "ocp-cad-viewer";

  targetPkgs =
    pkgs:
    (with pkgs; [
      uv
      python312
      # OpenCascade (bundled in cadquery-ocp wheels) runtime libraries
      stdenv.cc.cc.lib
      libGL
      libGLU
      glib
      fontconfig
      freetype
      expat
      zlib
      dbus
      libxkbcommon
      wayland
      # OpenCascade / Qt runtime X libraries (top-level since the xorg set
      # was deprecated in nixpkgs).
      libx11
      libxext
      libxmu
      libxi
      libxrender
      libxrandr
      libxfixes
      libxcursor
      libxinerama
      libsm
      libice
    ]);

  runScript = bootstrap;

  meta = with lib; {
    description = "OCP CAD Viewer backend (build123d/cadquery/ocp_vscode) via uv in an FHS sandbox";
    homepage = "https://github.com/bernhard-42/vscode-ocp-cad-viewer";
    license = licenses.asl20;
    maintainers = [ ];
    mainProgram = "ocp-cad-viewer";
  };
}
