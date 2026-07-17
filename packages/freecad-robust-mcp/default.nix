{
  lib,
  python3Packages,
  fetchPypi,
}:
# Host-side MCP server (PyPI: freecad-robust-mcp) that AI clients launch and
# which bridges to the in-FreeCAD "Robust MCP Bridge" workbench over XML-RPC
# (9875) / JSON-RPC socket (9876). The workbench itself is a FreeCAD addon
# installed via FreeCAD's Addon Manager, not packaged here.
python3Packages.buildPythonApplication rec {
  pname = "freecad-robust-mcp";
  version = "0.6.1";
  pyproject = true;

  src = fetchPypi {
    pname = "freecad_robust_mcp";
    inherit version;
    hash = "sha256-CY8phkFj3luySdfwpRD5Yqj/THa9a5VYZc9qFXHfmSg=";
  };

  build-system = with python3Packages; [
    hatchling
    hatch-vcs
  ];

  dependencies = with python3Packages; [
    mcp
    pydantic
    pydantic-settings
  ];

  # No test suite ships in the sdist.
  doCheck = false;

  pythonImportsCheck = [ "freecad_mcp" ];

  meta = with lib; {
    description = "Robust MCP server for FreeCAD integration with AI assistants";
    homepage = "https://github.com/spkane/freecad-robust-mcp-and-more";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "freecad-mcp";
  };
}
