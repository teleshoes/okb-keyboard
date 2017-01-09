#! /bin/bash -e

cd $(dirname "$0")
osver="sfos2"
if version | awk '{ print $2 }' | grep '^1\.' >/dev/null ; then osver="sfos1" ; fi
ln -sf "okboard_${osver}.qml" "okboard.qml"
