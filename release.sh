#! /bin/sh -e

BRANCH="master"
RPMBUILD="$HOME/rpmbuild"

cd `dirname "$0"`

[ -f "./version.cf" ]

. ./version.cf

if [ ! -d "../okb-engine" ]; then
    echo "../okb-engine not found: okboard & okb-engine must be unpacked under the same directory"
    exit 1
fi

full=
if [ "$1" = "-f" ] ; then
    full=1
else
    echo "usage: "`basename "$0"`" [-f]"
    exit 1
fi

echo ${DB_VERSION:-0} > db.version

pushd ../okb-engine/ngrams
python3 setup-cdb.py build
python3 setup-fslm.py build
machine=`uname -m`
libpath=`find build/ -type d -name "lib.*" | grep "$machine"`
export PYTHONPATH=${PYTHONPATH}:`pwd`"/$libpath"
popd


pushd ../okb-engine/db
for t in ??.tre ; do
    lang=`basename $t .tre`
    upd=
    version=`../tools/db_param.py "predict-$lang.db" version | awk '{ print $3 }'`
    if [ "$version" != "$DB_VERSION" ] ; then
	echo $DB_VERSION > db.version
	echo "Updating DB version: $version -> $DB_VERSION"
	../tools/db_param.py "predict-$lang.db" version $DB_VERSION
	upd=1
    fi

    if [ ! "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" ] ; then
	upd=1
    else
	[ "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -ot "$lang.tre" ] && upd=1
	[ "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -ot "predict-$lang.db" ] && upd=1
    fi
    if [ -n "$upd" ] ; then
	../tools/db_reset.py "predict-$lang.db"
	sleep 1
	tar cvfj "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" "$lang.tre" "predict-$lang.db" "predict-$lang.ng"
    fi
done
popd

cd ..

for proj in okboard okb-engine ; do
    pushd $proj
    tar="$RPMBUILD/SOURCES/$proj-$VERSION.tar.gz"
    if ! [ -f "$tar" ] || find . -type f -newer "$tar" | grep '^' >/dev/null ; then
	git archive -o "$tar" --prefix="$proj-$VERSION/" "$BRANCH"
    fi
    popd
done

if [ -n "$full" ] ; then
    specs="okboard/rpm/okboard-full.spec"
else
    specs="okboard/rpm/okboard.spec okb-engine/rpm/okb-engine.spec"
fi

for spec in $specs ; do
    perl -pi -e 's/^(Version:\s+).*$/${1}'"$VERSION"'/ ; s/^(Release:\s+).*$/${1}'"$RELEASE"'/' $spec
    cp -vf $spec $RPMBUILD/SPECS/
    fakeroot rpmbuild -ba $RPMBUILD/SPECS/`basename "$spec"`
done



