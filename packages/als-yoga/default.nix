{ buildPythonApplication, python, stdenv, xrandr }:


buildPythonApplication {
  name = "als-yoga";
  version = "0.1";
  src = ./.;

  propagatedBuildInputs = with python.pkgs; [ dbus-python pygobject3 xrandr ];

  meta = with stdenv.lib; {
    description = "Control OLED display and keyboard backlight brightness from ALS";
    homepage = https://github.com/georgewhewell/als-yoga;
    license = licenses.gpl2;
    maintainers = with maintainers; [ georgewhewell ];
  };
}
