{ pkgs }:

pkgs.writeScriptBin "oled-brightness" ''
  OLED_BR=`${pkgs.xorg.xrandr}/bin/xrandr --verbose | grep -i brightness | cut -f2 -d ' '`
  CURR=`LC_ALL=C printf "%.*f" 1 $OLED_BR`
  MIN=0
  MAX=1.2

  if [ "$1" == "up" ]; then
      VAL=`echo "scale=1; $CURR+0.1" | bc`
  else
      VAL=`echo "scale=1; $CURR-0.1" | bc`
  fi

  if (( `echo "$VAL < $MIN" | bc -l` )); then
      VAL=$MIN
  elif (( `echo "$VAL > $MAX" | bc -l` )); then
      VAL=$MAX
  else
      if [ "$1" == "up" ]; then
          for I in {1..10..1}; do ${pkgs.xorg.xrandr}/bin/xrandr --output eDP-1 --brightness `echo "scale=2; $I/100+$CURR" | ${pkgs.bc}/bin/bc` 2>&1 >/dev/null | logger -t oled-brightness; done
      else
          for I in {1..10..1}; do ${pkgs.xorg.xrandr}/bin/xrandr --output eDP-1 --brightness `echo "scale=2; $CURR-$I/100" | ${pkgs.bc}/bin/bc` 2>&1 >/dev/null | logger -t oled-brightness; done
      fi
  fi
''
