#! /bin/bash -e
# install packages to device (obviously needs ssh key to nemo & root accounts)

ARCH="armv7hl"

uninstall=
full=1
case "$1" in
    -m) full=0 ; shift ;;
    -u) uninstall=1 ; shift ;;
    -f) true ; shift ;; # backward compatible
    -*) echo "usage: "`basename "$0"`" [-m|-u]" ; exit 1 ;;
esac

device="$1"
if [ -z "$device" ] ; then
    echo "usage: "`basename "$0"`"[-u|-f] <device name or address>"
    exit 1
fi

cd `dirname "$0"`

. ./version.cf

arch=`ssh nemo@$device uname -m`
case "$arch" in
    armv7l|aarch64) ARCH="armv7hl" ;;  # Jolla phone
    x86_64) ARCH="i486" ;; # Jolla tablet
    *) echo "Unknown device ($arch)" ; exit 1 ; break ;;
esac

rpmf() {
    RPMS="$*"
    RPM_FILES=
    for rpm in $RPMS; do
	arch="$ARCH"
	echo "$rpm" | grep lang >/dev/null && arch="noarch"
	RPM_FILES="$HOME/rpmbuild/RPMS/$arch/$rpm-$VERSION-$RELEASE.$arch.rpm "
	ssh root@$device "rpm -q $rpm && rpm -e $rpm" || true
    done
}

rpmf okboard-full
rpmfull="${RPM_FILES}"
rpmf okboard okb-lang-en okb-lang-fr okb-engine
[ -n "$full" ] && RPM_FILES="${rpmfull}"

if [ -z "$uninstall" ] ; then
    TMP="/tmp"
    echo "Packages: $RPM_FILES"
    echo "Temporary install dir: $TMP"

    scp $RPM_FILES "nemo@$device:$TMP/"

    device_files=
    for rpm in $RPM_FILES ; do
	device_files="${device_files}$TMP/$(basename "$rpm") "
    done

    ssh root@$device "rpm -i $device_files && rm -vf $device_files"
fi
