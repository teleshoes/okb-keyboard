#! /bin/sh -e
# install packages to device (obviously needs ssh key to nemo & root accounts)

ARCH="armv7hl"

device="$1"
if [ -z "$device" ] ; then 
    echo "usage: "`basename "$0"`" <device name or address>"
    exit 1
fi

cd `dirname "$0"`

. ./version.cf

rsync -av --include 'okb*' $HOME/rpmbuild/RPMS/ nemo@$device:rpmbuild/RPMS/

RPMS="okboard okb-engine okb-lang-en okb-lang-fr"

echo "RPMS: $RPMS"
for rpm in $RPMS ; do
    arch="$ARCH"
    echo "$rpm" | grep lang >/dev/null && arch="noarch"
    RPM_FILES="${RPM_FILES}/home/nemo/rpmbuild/RPMS/$arch/$rpm-$VERSION-$RELEASE.$arch.rpm "
    ssh root@$device "rpm -q $rpm && rpm -r $rpm" || true
done

echo "Path: $RPM_FILES"

ssh root@$device "rpm -i $RPM_FILES"
