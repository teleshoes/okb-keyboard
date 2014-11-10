OKboard aka magic keyboard for Jolla
====================================

Description
-----------
This is a simple gesture based keyboard for Jolla phones.
It reuses most files from the official Jolla keyboard.
It contains modified files from Jolla keyboard, but these files where explicitely licensed as a BSD-like license (they comme from the original maliit plugins), so we are OK.
It is based on OKboard-engine for gesture recognition.

Limitations
-----------
This was only intended as a proof of concept and not as a real product, so it has a minimal feature set: it's just a standard Jolla keyboard with gesture typing ability, so it may break with any SailfishOS update.

Jolla does not provide settings to switch between different maliit plugins (keyboards): Settings app only allows to switch between languages in Jolla keyboard.
As a result we provide our keyboard switcher as part of the OKboard setting application.
This is a really dirty hack and may cause problems (e.g. conflict with other keyboards that would do the same).

How to build
------------
qmake / make for C++ part.

RPM .spec file is included for packaging.

How to run
----------
You can activate / deactivate OKboard from the settings application when RPMs are installed.

You can also run it from the source directory without installing (helpful for development):
Just unzip both okb-engine and okboard source code under the same directory, then launch "run.sh" script.
To return to normal operation, just remove `~/.config/maliit.org/server.conf` and restart maliit (`killall maliit-server`).
Note: this does not work when the OKboard RPMs are installed because they take precedence in the QML path.

TODO
----
This is just an indication of features missing for a full featured product (IMO). The keyboard should probably be redone as a proper maliit plugin.

* display candidates menu when user clicks on a previously entered word
* Maliit plugin choice should be handled by the OS (post a request on TJC)
* better spacing and punctuation handling (depends on language)
* shift on long press (as done by Skeyer project)
* hunt-and-peck typing should share the same word prediction database as gesture typing
* make an harbour compliant package (needs some path modifications, and support for pyotherside)
* "steal" predictions from Xt9 engine to improve ours :-)
