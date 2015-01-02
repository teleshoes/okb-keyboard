#! /bin/sh -e

BRANCH="master"
RPMBUILD="$HOME/rpmbuild"

cd `dirname "$0"`

[ -f "./version.cf" ]

. ./version.cf

V="${VERSION}-${RELEASE}"
N="okboard-${V}"
mkdir -p "/tmp/${N}"

for p in "armv7hl/okboard-${V}" "armv7hl/okb-engine-${V}" "noarch/okb-lang-fr-${V}" "noarch/okb-lang-en-${V}" ; do
    cp -vf "$HOME/rpmbuild/RPMS/$p"* "/tmp/${N}/"
done

cd /tmp
rm -f "${N}.zip"
zip -r9 "${N}.zip" "${N}"

echo "Zip OK: /tmp/${N}.zip"
