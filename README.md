OKboard aka magic keyboard for Jolla
====================================

Description
-----------
This is a simple gesture based keyboard for Jolla phones.

It contains modified files from Jolla keyboard, but these files were explicitely licensed as a BSD-like license (they comme from the original maliit plugins), so we are OK.
It uses okb-engine libraries for gesture recognition and prediction engine.

Limitations
-----------
* This is only intended as a proof of concept so there is no additional feature except gesture typing ability
* We use files from the Jolla keyboard, so the keyboard may break with any SailfishOS future update (use it at your own risk, but it never happened with update 4 to 11)
* Jolla does not provide settings to switch between different maliit plugins (keyboards): Current settings app only allows to switch between languages in Jolla keyboard. As a result we provide our keyboard switcher as part of the OKboard setting application: This is a really dirty hack and may cause problems (e.g. conflict with other applications that would do the same)

How to build & deploy
---------------------
To build everything (OKBoard + engine):

First get a build environment.

How to prepare a standard Jolla SDK (recommended solution):
* Start the SDK VM and connect with ssh, e.g.: `ssh -i <SDK install dir>/vmshare/ssh/private_keys/engine/mersdk -p 2222 mersdk@localhost`
* Run the following command to make sure Scratchbox will build with an ARM target: `sb2-config -d SailfishOS-armv7hl`
* Enter the scratchbox environment: `sb2`
* From inside the scratchbox2 enviroment, install required packages: `fakeroot zypper install python3-devel qt5-qtdeclarative-qtquick-devel meego-rpm-config git fakeroot libsailfishapp-devel`
* Make sure nemo user has a `rpmbuild` directory under its home directory with the following subdirectories: BUILD, BUILDROOT, RPMS, SOURCES, SPECS, SRPMS
* Note: You can access your host home directory under `~/share/` if needed

How to prepare an ARM chroot environment (for building on device or with qemu). As you are supposed to know what you're doing, this is just rough overview:
* Build your chroot environent, e.g. https://together.jolla.com/question/26605/howto-install-a-chroot-for-building-apps/
* As root, install required packages (cf. zypper command above without "fakeroot")
* You can now build from unpriviledged user

In any case you have to unpack language files under `okb-engine/db/` directory because they are not included in the git repository (more details in okb-engine README file)

How to build the RPMs from your build environment:
* Unpack okboard and okb-engine source code under a common directory
* If you need to change version number, update `version.cf` file with version information (under okboard directory)
* If you have done any changes, you'll need to commit them (as our script use `git archive`)
* Produce RPM package by running the `release.sh` under okboard source directory.
  By default, the script will produce one RPM file for keyboard, engine and each language file (use `-m` option if you prefer multiple RPMs, this is not recommended)

How to deploy RPMs to your Jolla phone:
* You can manually transfer the RPM to your Jolla phone and install it with `rpm -i` (as root)
* Alternatively, run `deploy.sh <host or IP>` (deploy.sh script is under okboard directory). If you added `-m` option for release, you also have to add it to deploy.sh script. This script requires ssh keys to connect as root to the phone
* enjoy :-)

How to run
----------
You can activate / deactivate OKboard from the settings application when RPMs are installed.

Test mode: You can also run it from the source directory without installing (helpful for development):
Just unzip both okb-engine and okboard source code under a common directory and manually build all C/C++ parts with make/qmake.
Launch `run.sh` script.
To return to normal operation, just remove `~/.config/maliit.org/server.conf` and restart maliit (`killall maliit-server`).
Note: this does not work when the OKboard RPMs are installed because they take precedence in the QML path.

TODO
----
* The keyboard should probably be redone as a standalone maliit plugin (no reliance on Jolla keyboard files)
* Display candidates menu when user clicks on a previously entered word
* Maliit plugin choice should be handled by the OS: post a request on TJC or sailfishOS mailing-list
* Better spacing and punctuation handling (depends on language)
* Shift on long press (as done by Skeyer project)
* Hunt-and-peck typing should share the same word prediction database as gesture typing
* Make an harbour compliant package (needs some path modifications. Pyotherside support is supposed to be available)
* "Steal" predictions from Xt9 engine to improve ours :-)
