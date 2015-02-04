#! /bin/sh -e
# run okboard in test mode:
#  - all data files are in /tmp (so we don't damage user's "production" databases)
#  - and restart maliit-server with modified environment & configuration file

ENGINE="../okb-engine"

cd `dirname "$0"`
mydir=`pwd`

die() { echo "ERR: $*" ; exit 1 ; }

ENGINE=`realpath "$ENGINE"`

[ -d "$ENGINE" ] || die "okb-engine must be unpacked in the same directory as okb-keyboard"

# set up maliit configuration file
conffile="$HOME/.config/maliit.org/server.conf"
cat "$mydir/server.conf" | sed 's+^paths=.*+paths='"$mydir/plugin"'+' | tee "$conffile"
[ -f "$conffile" ] || die "Configuration file not found: $conffile"

# environment
OKBOARD_TEST_DIR=/tmp  # let's use /tmp (beware of tmpfs ram usage)
[ -f "$HOME/.okboard-test" ] && . $HOME/.okboard-test
export QML2_IMPORT_PATH="$mydir/qml"
export OKBOARD_TEST_DIR
rm -f "$OKBOARD_TEST_DIR/okboard.cf" # always start with default params
echo "Test directory: $OKBOARD_TEST_DIR"

ngram_lib=`find "$ENGINE/ngrams/build/" -type d -name "lib.*"`
[ -d "$ngram_lib" ] || die "Error finding ngram library: $ngram_lib"
export PYTHONPATH="$PYTHONPATH:$ngram_lib"

# link to okb-engine C++ plugin
qmldir="$mydir/qml/eu/cpbm/okboard"
SO="$ENGINE/curve/build/libcurveplugin.so"
[ -x "$SO" ] || die "libcurveplugin.so hasn't been compiled"
ln -sf "$SO" "$qmldir/libcurveplugin.so"

# symlink to a needed jolla-keyboard file
N="touchpointarray.js"
JS="/usr/share/maliit/plugins/com/jolla/$N"
[ -L "$qmldir/$N" ] || ln -vs "$JS" "$qmldir/$N"

# symlink to python stuff (avoids declaring new paths)
[ -L "predict.py" ] || ln -svf "$ENGINE/predict.py" "$qmldir/"

# symlink to default preference
[ -L "$qmldir/okboard.cf" ] || ln -svf "$ENGINE/okboard.cf" "$qmldir/okboard.cf"

# check data directory
if [ -d "$ENGINE/db" ] ; then
    find "$ENGINE/db/" -name '*.tre' | grep '^' >/dev/null || die "$ENGINE/db must contains some .tre & .db files"
    cp -avfu $ENGINE/db/??.tre $ENGINE/db/predict-??.db $ENGINE/db/predict-??.ng "$OKBOARD_TEST_DIR/"  # allow databases to be modified
fi

# restart maliit
systemctl --user stop maliit-server.service
killall maliit-server 2>/dev/null || true
echo "Starting maliit-server ..."
maliit-server &
