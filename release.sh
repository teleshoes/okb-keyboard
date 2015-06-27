#! /bin/bash -e

BRANCH="master"
RPMBUILD="$HOME/rpmbuild"

cd `dirname "$0"`
pwd=`pwd`
okboard_dir=`basename "$pwd"`

[ -f "./version.cf" ]

. ./version.cf

if [ ! -d "../okb-engine" ]; then
    echo "../okb-engine not found: okboard & okb-engine must be unpacked under the same directory"
    exit 1
fi

full=1
case "$1" in
    -m) full=0 ; shift ;;
    -f) true ; shift ;; # backward compatible
    -*) echo "usage: "`basename "$0"`" [-m]" ; exit 1 ;;
esac

pushd ../okb-engine/db
all_lang="$LANGS"
[ -n "$all_lang" ] || all_lang=`ls *.cf | sed 's/^lang-//' | sed 's/\.cf$//' | tr '\n' ' '`
echo "Language supported: $all_lang"
for lang in $all_lang ; do
    if [ ! -f "$lang.tre" -o ! -f "predict-$lang.db" -o ! -f "predict-$lang.ng" ] ; then
	echo "Error: missing language files under "`pwd`" directory"
	exit 1
    fi
done
popd

pwd=`pwd`
tools_dir="$pwd/../okb-engine/tools"

echo ${DB_VERSION:-0} > db.version
echo ${CF_VERSION:-0} > cf.version

pushd ../okb-engine/ngrams
find build/ -name 'lib.*' -type d | xargs rm -rf  # remove build dir (in case of older version in build dir)
python3 setup-cdb.py build
python3 setup-fslm.py build
machine=`uname -m`
libpath=`find build/ -type d -name "lib.*" | grep "$machine"`
echo "Python libpath: $libpath"
export PYTHONPATH=${PYTHONPATH}:`pwd`/"$libpath"
popd


tmp_dir=`mktemp -d`
for lang in $all_lang ; do
    cp -vf ../okb-engine/db/*${lang}.{db,ng,tre} $tmp_dir/
done

pushd $tmp_dir
for lang in $all_lang ; do
    upd=
    version=`$tools_dir/db_param.py "predict-$lang.db" version | awk '{ print $3 }'`
    if [ "$version" != "$DB_VERSION" ] ; then
	echo "Updating DB version: $version -> $DB_VERSION"
	python3 $tools_dir/db_param.py "predict-$lang.db" version $DB_VERSION
	upd=1
    fi

    if [ ! "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" ] ; then
	upd=1
    else
	[ "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -ot "$lang.tre" ] && upd=1
	[ "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -ot "predict-$lang.db" ] && upd=1
    fi
    if [ -n "$upd" ] ; then
	python3 $tools_dir/db_reset.py "predict-$lang.db"
	sleep 1
	tar cvfj "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" "$lang.tre" "predict-$lang.db" "predict-$lang.ng"
    fi
done
rm -f *.{db,ng,tre}
popd
rmdir $tmp_dir

cd ..

for proj in okboard okb-engine ; do
    projdir="$proj"
    [ "$proj" = "okboard" ] && projdir="$okboard_dir"  # workaround for my badly named git repo

    pushd $projdir
    tar="$RPMBUILD/SOURCES/$proj-$VERSION.tar.gz"
    if ! [ -f "$tar" ] || find . -type f -newer "$tar" | grep '^' >/dev/null ; then
	git archive -o "$tar" --prefix="$proj-$VERSION/" "$BRANCH"
    fi
    popd
done

if [ -n "$full" ] ; then
    specs="$okboard_dir/rpm/okboard-full.spec"
else
    specs="$okboard_dir/rpm/okboard.spec okb-engine/rpm/okb-engine.spec"
fi

for spec in $specs ; do
    perl -pi -e 's/^(Version:\s+).*$/${1}'"$VERSION"'/ ; s/^(Release:\s+).*$/${1}'"$RELEASE"'/' $spec
    cp -vf $spec $RPMBUILD/SPECS/
    fakeroot rpmbuild -ba $RPMBUILD/SPECS/`basename "$spec"`
done

