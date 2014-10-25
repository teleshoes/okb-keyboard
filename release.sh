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

pushd ../okb-engine/db
for t in ??.tre ; do
    lang=`basename $t .tre`
    if ! [ "$lang.tre" -ot "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" -a "predict-$lang.db"  -ot "$RPMBUILD/SOURCES/okb-lang-$lang.tar.bz2" ] ; then
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



