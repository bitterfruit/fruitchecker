#!/bin/bash

uninstallonubuntu () {
  # do the bizz
  [[ "$USER" != "root" ]] && {
    echo "Error: Script must be runned with root access. Use sudo."; exit 1;
  }
  rm -v /usr/local/bin/fruitcheck
  rm -v "$HOME/Desktop/fruitcheck.desktop"
  # rm -v /usr/share/applications/fruitcheck.desktop
  # rm -v /usr/share/pixmaps/Cherry-icon_48.png
}

uninstalloncygwin () {
  rm -v /usr/local/bin/fruitcheck
  rm -v "$HOME/.bashrcfruitcheck"
  rm -v "$(cygpath "$USERPROFILE")/Desktop/FruitCheck.bat"

}
#http://stackoverflow.com/questions/592620/how-to-check-if-a-program-exists-from-a-bash-script

echo "Install-script for FruitCheck."
fail=0

# Determine OS
hash uname >/dev/null 2>&1 && { unamis=$(uname -a); }
if [ -n "$unamis" ]; then
	[[ "$unamis" == CYGWIN* ]]  && { mydistro="Cygwin"; }
	[[ "$unamis" == *Ubuntu* ]] && { mydistro="Ubuntu"; }
else
	[[ "$OS" == *Windows* ]] && { mydistro="Cygwin"; }
fi

[ -z $mydistro ] && { echo "ERROR: Unable to determine distro"; exit 1; }
[[ "$mydistro" == "Ubuntu" ]] && { uninstallonubuntu; }
[[ "$mydistro" == "Cygwin" ]] && { uninstalloncygwin; }

answer=""
[ -f "$HOME/.fruitcheck" ] && {
  read -n1 -p"Do you want to remove the config file ? (y/n) " answer
  echo ""
  [[ "$answer" == "y" ]] && {
    [ -f "$HOME/.fruitcheck" ] && { rm -v "$HOME/.fruitcheck"; };
  }
}
 
exit 0;

