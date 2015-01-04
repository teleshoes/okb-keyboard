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

echo ${DB_VERSION:-0} > db.version

pushd ../okb-engine/db
for t in ??.tre ; do
    lang=`basename $t .tre`
    upd=
    version=`sqlite3 "predict-$lang.db" "select * from version"`
    if [ "$version" != "$DB_VERSION" ] ; then
	echo "Updating DB version: $version -> $DB_VERSION"
	sqlite3 "predict-$lang.db" "update version set version=$DB_VERSION"
	upd=1
    fi

    if [ ! "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" ] ; then
	upd=1
    else
	[ "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -ot "$lang.tre" ] && upd=1
	[ "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -ot "predict-$lang.db" ] && upd=1
    fi
    if [ -n "$upd" ] ; then
	../tools/dbreset.sh "predict-$lang.db"
	sleep 1
	tar cvfj "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" "$lang.tre" "predict-$lang.db"
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
    perl -pi -e 's/^(Version:\s+).*$/${1}'"$VERSION"'/ ; s/^(Release:\s+).*$/${1}'"$RELEASE"'/' rpm/$proj.spec
    cp -vf rpm/$proj.spec $RPMBUILD/SPECS/
    popd
    fakeroot rpmbuild -ba $RPMBUILD/SPECS/$proj.spec
done



