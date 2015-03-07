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
To build everything (OKBoard + engine) :
* unpack okboard and okb-engine source code under a common directory
* if needed, update `version.cf` file with version information (under okboard directory)
* commit any change to be included (our script use `git archive`)
* produce RPM packages by running the `release.sh` script from an ARM environment that can run Sailfish build toolchain (SDK, scratchbox, chroot ...)
* run `deploy.sh <host or IP>` to deploy RPM packages to an existing Jolla phone (this requires ssh keys to connect as root to the phone). Alternatively you can just manually use `rpm -i`
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
