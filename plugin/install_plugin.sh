#! /bin/bash -e

target_dir="$1"

mydir=$(dirname "$0")
if version | awk '{ print $2 }' | grep '^1\.' >/dev/null ; then
    patch -o "$target_dir/okboard.qml" "$mydir/okboard.qml" "$mydir/okboard_2to1.diff"
else
    cp -f "$mydir/okboard.qml" "$target_dir/okboard.qml"
fi

chmod 644 "$target_dir/okboard.qml"
