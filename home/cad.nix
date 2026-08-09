{
  config,
  pkgs,
  lib,
  ...
}: let
  # Forces a browser User-Agent on requests so EasyEDA's CloudFront doesn't 403
  # the hardcoded "easyeda2kicad v<ver>" UA.
  easyedaUaPatch = pkgs.writeTextDir "sitecustomize.py" ''
    import builtins

    _BROWSER_UA = (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    )

    _orig_import = builtins.__import__
    _patched = False


    def _apply_patch():
        global _patched
        if _patched:
            return
        import requests

        _orig_request = requests.Session.request

        def _patched_request(self, method, url, **kw):
            headers = dict(kw.get("headers") or {})
            ua = headers.get("User-Agent", "")
            if not ua or "easyeda2kicad" in ua or "python-requests" in ua:
                headers["User-Agent"] = _BROWSER_UA
                kw["headers"] = headers
            return _orig_request(self, method, url, **kw)

        requests.Session.request = _patched_request
        _patched = True


    def _hooked_import(name, *a, **kw):
        mod = _orig_import(name, *a, **kw)
        if not _patched and (name == "requests" or name.startswith("requests.")):
            try:
                _apply_patch()
            except Exception:
                pass
        return mod


    builtins.__import__ = _hooked_import
  '';
in {
  home.packages = with pkgs; [
    # Electronics
    kicad-unstable
    easyeda2kicad
    freerouting
    ngspice

    # 3D CAD / Modeling
    freecad-wayland
    openscad-unstable

    # 3D printing: slicer for the Bambu printer (from nixpkgs; the
    # proprietary networking plugin is not shipped — open-bamboo-networking
    # is a possible follow-up if cloud/LAN connectivity is needed).
    bambu-studio

    # FreeCAD <-> AI via the Robust MCP bridge. Provides the `freecad-mcp`
    # server; install the matching "Robust MCP Bridge" workbench inside
    # FreeCAD via Tools -> Addon Manager.
    freecad-robust-mcp

    # OCP CAD Viewer backend for build123d/cadquery. `ocp-cad-viewer` drops
    # into a venv shell; `ocp-cad-viewer serve` runs the viewer on :3939.
    ocp-cad-viewer

  ];

  # `easyeda <LCSC_ID>` — from anywhere inside a KiCad project: walks up to find
  # the .kicad_pro, downloads symbol+footprint+3D into <project>/libs/<ID>, and
  # appends entries to sym-lib-table / fp-lib-table (creating them if missing).
  programs.zsh.initContent = ''
    easyeda() {
      if [ -z "$1" ]; then
        echo "usage: easyeda <LCSC_ID>  (e.g. easyeda C492541)" >&2
        return 1
      fi
      local id="$1"
      shift

      # Walk up from cwd looking for a .kicad_pro
      local proj_dir="$PWD"
      while [ "$proj_dir" != "/" ] && ! ls "$proj_dir"/*.kicad_pro > /dev/null 2>&1; do
        proj_dir="$(dirname "$proj_dir")"
      done
      if [ "$proj_dir" = "/" ]; then
        echo "easyeda: no .kicad_pro found in $PWD or any parent" >&2
        return 1
      fi
      echo "easyeda: using project at $proj_dir"

      mkdir -p "$proj_dir/libs"
      ( cd "$proj_dir" && PYTHONPATH=${easyedaUaPatch} ${pkgs.easyeda2kicad}/bin/easyeda2kicad \
          --full --lcsc_id "$id" --output "libs/$id" --project-relative "$@" ) || return $?

      local sym_tbl="$proj_dir/sym-lib-table"
      local fp_tbl="$proj_dir/fp-lib-table"
      [ -f "$sym_tbl" ] || printf '%s\n' "(sym_lib_table" "  (version 7)" ")" > "$sym_tbl"
      [ -f "$fp_tbl" ]  || printf '%s\n' "(fp_lib_table"  "  (version 7)" ")" > "$fp_tbl"

      local sym_line="  (lib (name \"$id\")(type \"KiCad\")(uri \"\''${KIPRJMOD}/libs/$id.kicad_sym\")(options \"\")(descr \"\"))"
      local fp_line="  (lib (name \"$id\")(type \"KiCad\")(uri \"\''${KIPRJMOD}/libs/$id.pretty\")(options \"\")(descr \"\"))"

      if grep -q "(name \"$id\")" "$sym_tbl"; then
        echo "easyeda: $id already in sym-lib-table"
      else
        sed -i "\$i\\$sym_line" "$sym_tbl"
        echo "easyeda: added $id to sym-lib-table"
      fi
      if grep -q "(name \"$id\")" "$fp_tbl"; then
        echo "easyeda: $id already in fp-lib-table"
      else
        sed -i "\$i\\$fp_line" "$fp_tbl"
        echo "easyeda: added $id to fp-lib-table"
      fi

      echo "easyeda: done — in KiCad, close the schematic/PCB editor windows and reopen them (tables are read on editor open)"
    }
  '';
}
