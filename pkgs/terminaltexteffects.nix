{ lib
, python3Packages
, fetchPypi
}:

python3Packages.buildPythonApplication rec {
  pname = "terminaltexteffects";
  version = "0.10.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-NyWPfdgLeXAxKPJOzB7j4aT+zjrURN59CGcv0Vt99y0=";
  };

  build-system = with python3Packages; [
    poetry-core
  ];
}
