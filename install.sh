#!/bin/bash
installfailed () { echo "Installation failed. Exitting."; exit 1; }

installonubuntu () {
  # do the bizz
  [[ "$USER" != "root" ]] && {
    echo "Error: Script must be runned with root access. Use sudo."; exit 1;
  }
  installperl=0
  installperltk=0
  installlibarc=0
  installzenity=0
  if hash perl >/dev/null 2>&1; then
    echo "You have perl ... OK"
  else
    answer=""
    read -n1 -p"PERL is missing, install it? (y/n)" answer
    echo ""
    echo ""
    [[ "$answer" == "y" ]] && { installperl=1; } || { installfailed; }
  fi
  if dpkg -s perl-Tk 2>&1|grep "Status: install ok" >/dev/null; then
    echo "You have perl-tk ... OK"
  else
    answer=""
    read -n1 -p"The package perl-tk is needed, install it? (y/n) " answer
    echo ""
    [[ "$answer" == "y" ]] && { installperltk=1; } || { installfailed; }
  fi
  if dpkg -s libarchive-zip-perl 2>&1|grep "Status: install ok" >/dev/null; then
    echo "You have libarchive-zip-perl ... OK"
  else
    answer=""
    read -n1 -p"The package libarchive-zip-perl is needed, install it? (y/n) " answer
    echo ""
    [[ "$answer" == "y" ]] && { installlibarc=1; } || { installfailed; }
  fi

  if dpkg -s zenity 2>&1|grep "Status: install ok" >/dev/null; then
    echo "You have zenity ... OK"
  else
    answer=""
    echo "Package zenity is recomended for pretty SelectDirectory Dialogs."
    echo "(which is nicer than the ancient perltk variant)"
    read -n1 -p"Install package zenity now? (y/n) " answer
    echo ""
    [[ "$answer" == "y" ]] && { installzenity=1; }
  fi
  [[ $installperl -eq 1 ]] && { apt-get install perl; }
  [[ $installperltk -eq 1 ]] && { apt-get install perl-tk; }
  [[ $installlibarc -eq 1 ]] && { apt-get install libarchive-zip-perl; }
  [[ $installzenity -eq 1 ]] && { apt-get install zenity; }

  echo "Installing fruitcheck -> /usr/local/bin/fruitcheck"
  cp fruitcheck.pl /usr/local/bin/fruitcheck || { installfailed; }
  chmod 755 /usr/local/bin/fruitcheck || { installfailed; }

  if [ -d /usr/share/pixmaps ] ; then
    cp -v ./Cherry-icon_48.png /usr/share/pixmaps || { echo "Unable to copy icon image"; }
    if [ -d $HOME/Desktop ] ; then
      cp -v ./fruitcheck.desktop $HOME/Desktop
      cp -v ./fruitcheck.desktop /usr/share/applications
      chmod 715 $HOME/Desktop/fruitcheck.desktop
      chown $SUDO_USER $HOME/Desktop/fruitcheck.desktop
    else
      echo "Unable to locate folder \$HOME/Desktop. No icons copied."
      fail=1
    fi
  else
    echo "Unable to locate folder /usr/share/pixmaps. No icons copied."
    fail=1
  fi
  [ $fail -eq 1 ] && {
    echo "Script encountered trouble with installing icons."
    echo "FruitCheck can be launched by writing the command \"fruitcheck\".";
  }

}

installoncygwin () {
  failinstall=0
  hash perl >/dev/null 2>&1 && { echo "You have perl..OK"; } || { echo >&2 "Error: PERL must be installed."; failinstall=1; }
  cygcheck xinit >/dev/null 2>&1 && { echo "You have xinit (X11 server)..OK"; } || {
    echo "ERROR: You need to install the X11 package xinit.";
    echo "See http://x.cygwin.com/ for more installation instructions."
    failinstall=1;
  }
  cygcheck -c perl-tk|grep "OK" >/dev/null 2>&1 && { echo "You have perl-tk..OK"; } || {
    echo "ERROR: You need to install the perl-tk package.";
    failinstall=1;
  }
  cygcheck -c perl-Win32-GUI|grep "OK" >/dev/null 2>&1 && { echo "You have perl-Win32-GUI..OK"; }|| {
    echo "RECOMENDED: You can install perl-Win32-GUI package to get the propper BrowseForFile dialog.";
    echo "Without that package you'll get the UUGLAAY chooseDirectory dialog that comes with Perl-Tk.";
    [[ $failinstall -eq 0 ]] && { echo "Run Setup.exe to install packages."; }
  }
  [[ $failinstall -eq 1 ]] && { echo "Run Setup.exe to install packages.";
    installfailed;
  }
  echo "Installing fruitcheck -> /usr/local/bin/fruitcheck"
  cp fruitcheck.pl /usr/local/bin/fruitcheck || { installfailed; }
  chmod 755 /usr/local/bin/fruitcheck || { installfailed; }
  read -n1 -p"Do you want a launch icon (bat) on your desktop? (y/n) " answer
  echo ""
  [ "$answer" == y ] && {
    echo "Writing to a bashrc config -> $HOME/.bashrcfruitcheck"
		echo "unset TMP">$HOME/.bashrcfruitcheck
    echo "unset TEMP" >>$HOME/.bashrcfruitcheck
    echo "fruitcheck" >>$HOME/.bashrcfruitcheck
    echo "Writing to a bat file on desktop -> "$(cygpath "$USERPROFILE")"/Desktop/FruitCheck.bat"
    echo "C:\cygwin\bin\bash.exe --login -i .bashrcfruitcheck" >"$(cygpath "$USERPROFILE")/Desktop/FruitCheck.bat"
  }
}
#http://stackoverflow.com/questions/592620/how-to-check-if-a-program-exists-from-a-bash-script

echo -e "\e[0m\e[4mInstall-script for FruitCheck.\e[0m"
echo ""
fail=0

# Determine OS
hash uname >/dev/null 2>&1 && { unamis=$(uname -a); }
if [ -n "$unamis" ]; then
	[[ "$unamis" == CYGWIN* ]]  && { mydistro="Cygwin"; }
	[[ "$unamis" == *Ubuntu* ]] && { mydistro="Ubuntu"; }
else
	[[ "$OS" == *Windows* ]] && { mydistro="Cygwin"; }
fi

[ -z $mydistro ] && { echo "ERROR: Unable to determine distro"; installfailed; }
[[ "$mydistro" == "Ubuntu" ]] && { installonubuntu; }
[[ "$mydistro" == "Cygwin" ]] && { installoncygwin; }

echo "Installation successful."
exit 0;

