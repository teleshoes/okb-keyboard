#! /usr/bin/python3
# -*- coding: utf-8 -*-

""" Technical stuff for okboard: error management, configuration management, logs ... """

try: import pyotherside
except: pyotherside = None

import os
import traceback
import configparser as ConfigParser
import json
import gzip
import shutil
import time
import glob
import subprocess

from predict import Predict

mybool = lambda x: False if str(x).lower() in [ "0", "false", "no", "off", "" ] else True

ABOUT = """
OKBoard aka Magic Keyboard for Jolla
http://projects.tuxfamily.org/?do=group;name=okboard
Contact: eb@cpbm.eu
License: BSD-like for Jolla Keyboard modifications, LGPL for engine

No tester has been harmed in the making of this software

=== Versions ===
"""

class Okboard:
    SHARE_PATH = "/usr/share/okboard"
    MALIIT_CONF_FILE = os.path.join(os.path.expanduser('~'), ".config/maliit.org/server.conf")

    def __init__(self):
        self.lang = None
        self.predict = Predict(self)
        self.last_conf = dict()
        self.orientation = None
        self.logf = None

        # add error management wrappers (this is probably no more necessary with pyotherside 1.2 error handler)
        self.guess = self.exception_wrapper(self.predict.guess)
        self.update_surrounding = self.exception_wrapper(self.predict.update_surrounding)
        self.get_predict_words = self.exception_wrapper(self.predict.get_predict_words)
        self.update_preedit = self.exception_wrapper(self.predict.update_preedit)
        self.replace_word = self.exception_wrapper(self.predict.replace_word)
        self.wake_up = self.exception_wrapper(self.predict.refresh_db)
        self.log_qml = self.exception_wrapper(self._log_qml)

        self.cleanup = self.exception_wrapper(self._cleanup)
        self.set_context = self.exception_wrapper(self._set_context)
        self.get_config = self.exception_wrapper(self._get_config)
        self.init = self.exception_wrapper(self._init)

        self.last_error = None
        self.cp = None

        self.init()
        print("okboard.py init complete")

    def get_last_error(self):
        tmp = self.last_error
        self.last_error = None
        return tmp

    def exception_wrapper(self, func):
        # this is an ugly wrapper to display exceptions because they do not seem to be handled by pyotherside or lost somewhere in js/qml
        def wrapper(*params, **kwargs):
            try:
                return func(*params, **kwargs)
            except Exception as e:
                for m in [ "Exception in function %s: %s" % (func.__qualname__, e),
                           traceback.format_exc() ]:
                    try: self.log(m)
                    except: pass
                self.last_error = "Error in %s: %s (see logs)" % (func.__qualname__, str(e))  # exception for display in GUI
                raise e  # trigger QML error handler
        return wrapper

    def _init(self):
        # init path
        test_dir = os.environ.get("OKBOARD_TEST_DIR", None)
        if not test_dir or test_dir.lower() in [ "0", "false" ]:
            # production mode
            self.config_dir = os.path.join(os.path.expanduser('~'), ".config/okboard")
            self.local_dir = os.path.join(os.path.expanduser('~'), ".local/share/okboard")
            if not os.path.isdir(self.config_dir): os.makedirs(self.config_dir)
            if not os.path.isdir(self.local_dir): os.makedirs(self.local_dir)
            test_mode = False
        else:
            # test mode
            self.config_dir = self.local_dir = test_dir if os.path.isdir(test_dir) else "/tmp"
            print("Test mode (working directory=%s)" % self.config_dir)
            test_mode = True

        # config files
        self.cp = cp = ConfigParser.SafeConfigParser()
        self.cpfile = os.path.join(self.config_dir, "okboard.cf")
        _default_conf = os.path.join(os.path.dirname(__file__), "okboard.cf")
        _dist_conf = os.path.join(Okboard.SHARE_PATH, "okboard.cf")
        cp.read([ _dist_conf, _default_conf, self.cpfile ])

        save = not os.path.isfile(self.cpfile)
        for s in [ "main", "default", "portrait", "landscape" ]:
            if s not in cp:
                cp[s] = {}
                save = True

        if save:
            cp["main"]["verbose"] = cp["main"]["log"] = "1" if test_mode else "0"
            cp["main"]["debug"] = "0"
            with open(self.cpfile, 'w') as f: cp.write(f)

        self.cptime = os.path.getmtime(self.cpfile)
        self.test_mode = test_mode

    def _get_config(self, only_if_modified = False):
        """ return some configuration elements for QML part """
        mtime = os.path.getmtime(self.cpfile)
        cp = self.cp
        if mtime > self.cptime:
            self.cptime = mtime
            cp.read(self.cpfile)

        # default parameters
        result = dict(config_dir = self.config_dir,
                      local_dir = self.local_dir,
                      log = self.cf("log", 0, mybool),
                      debug = self.cf("debug", 0, mybool))

        # curve parameters (depend on orientation)
        params = dict()
        for section in ["default", "landscape" if self.orientation in [90, 270] else "portrait" ]:
            params.update(cp[section])
        for p in params: params[p] = float(params[p])

        result["curve_params"] = json.dumps(params)
        result["disable"] = mybool(params.get("disable_orientation", False))

        if only_if_modified and result == self.last_conf: return dict(unchanged = True)
        self.last_conf = dict(result)

        return result

    def cf(self, key, default_value, cast = None):
        cp = self.cp
        if key in cp["main"]:
            ret = cp["main"][key]
        else:
            self._get_config()
            ret = default_value
            cp["main"][key] = str(default_value)
            with open(self.cpfile, 'w') as f: cp.write(f)

        if cast:
            try:
                ret = cast(ret)
            except:
                cp["main"][key] = str(default_value)
                with open(self.cpfile, 'w') as f: cp.write(f)
                ret = default_value
        return ret

    def set_cf(self, key, value):
        if key in self.cp["main"] and self.cp["main"][key] == str(value): return
        self.cp["main"][key] = str(value)
        with open(self.cpfile + '.tmp', 'w') as f: self.cp.write(f)
        os.rename(self.cpfile + '.tmp', self.cpfile)

    def log(self, *args, **kwargs):
        if not args:
            if self.logf:
                self.logf.write("\n")
                self.logf.close()
                self.logf = None
            return

        force_log = kwargs.get("force_log", False)
        message = ' '.join(map(str, args))
        print(message)
        if self.cf('log', False, mybool) or force_log:
            if not self.logf:
                self.logf = open(os.path.join(self.local_dir, "predict.log"), "a")
            self.logf.write(message + "\n")
            if force_log:
                self.logf.close()
                self.logf = None

    def _log_qml(self, jsargs):
        txt = ' '.join([ str(x[1]) for x in sorted(jsargs.items(), key = lambda x: int(x[0])) ])
        self.log('QML: ' + txt)

    def _set_context(self, lang, orientation):
        """ sets language and try to load DB """
        self.lang = lang
        self.orientation = orientation
        new_dbfile = os.path.join(self.local_dir, "predict-%s.db" % lang)
        if new_dbfile and self.predict.db and self.predict.dbfile == new_dbfile:
            pass  # no change, no need to reload
        else:
            self.predict.set_dbfile(new_dbfile)

        # copy distribution database to user home directory
        if self.lang and len(self.lang) >= 2 and not self.test_mode:
            for db in [ "predict-%s.db" % self.lang, "%s.tre" % self.lang ]:
                src = os.path.join(Okboard.SHARE_PATH, db + ".gz")
                dest = os.path.join(self.local_dir, db)
                if os.path.exists(src) and not os.path.exists(dest):
                    print("Deploying DB file %s -> %s" % (src, dest))
                    with gzip.open(src, 'rb') as rf:
                        with open(dest, 'wb') as wf:
                            shutil.copyfileobj(rf, wf)
        self.predict.load_db()

    def _cleanup(self, **kwargs):
        # log rotate
        rotate = self.cf("log_rotate", True, mybool)
        if rotate:
            logs = [ "curve.log", "predict.log" ]
            rotate_size = max(1, self.cf("rotate_mb", 5, int))
            for log in logs:
                fname = os.path.join(self.local_dir, log)
                if os.path.exists(fname) and os.path.getsize(fname) > rotate_size * 1000000:
                    if log == "predict.log": self.log()  # close log file
                    os.rename(fname, fname + ".bak")

        return self.predict.cleanup(**kwargs)

    def close(self):
        print("okboard.py exiting ...")
        self.predict.close()

    def get_version(self):
        try:
            with open(os.path.join(os.path.dirname(__file__), "okboard.version"), "r") as f:
                return f.read().strip()
        except:
            return "unknown"

    # --- functions for settings app ---

    def _restart_maliit_server(self):
        # restart maliit server to apply changes
        # (use the right maliit plugin, and reload databases and configuration)
        print("Restarting maliit server ...")
        subprocess.call(["killall", "maliit-server"])  # ouch !

    def stg_get_settings(self):
        keyboard_enabled = False
        if os.path.isfile(Okboard.MALIIT_CONF_FILE):
            conf = open(Okboard.MALIIT_CONF_FILE, "r").read()
            if conf.find("okboard") > -1: keyboard_enabled = True

        result = dict(log = self.cf("log", 1, mybool),
                      learn = self.cf("learning_enable", 1, mybool),
                      enable = keyboard_enabled)

        print("Settings:", result)
        return result

    def stg_enable(self, value):
        dir = os.path.dirname(Okboard.MALIIT_CONF_FILE)
        if not os.path.isdir(dir): os.mkdir(dir)
        with open(Okboard.MALIIT_CONF_FILE, 'w') as f:
            keyboard = "okboard" if value else "jolla-keyboard"
            f.write("[maliit]\n")
            f.write('onscreen\\active=%s.qml\n' % keyboard)
            f.write('onscreen\\enabled=%s.qml\n' % keyboard)

        self._restart_maliit_server()

    def stg_set_log(self, value):
        print("Settings: set log", value)
        self.set_cf("log", "1" if value else "0")

    def stg_set_learn(self, value):
        print("Settings: set learning", value)
        self.set_cf("learning_enable", value is True)

    def stg_clear_logs(self):
        logs = [ "curve.log", "predict.log" ]
        for log in logs:
            for log2 in [ log, log + '.bak' ]:
                fname = os.path.join(self.local_dir, log2)
                print("Removing %s (if present)" % fname)
                if os.path.isfile(fname): os.unlink(fname)
        self._restart_maliit_server()

    def stg_reset_all(self):
        print("Reseting all databases & settings")
        remove = (glob.glob(os.path.join(self.local_dir, "*.tre")) +
                  glob.glob(os.path.join(self.local_dir, "persist-*.db*")) +
                  glob.glob(os.path.join(self.config_dir, "okboard.cf")))
        for fname in remove:
            print("Removing %s" % fname)
            os.unlink(fname)
        # possible race condition here if keyboard decides to write its configuration again
        self._restart_maliit_server()

    def stg_about(self):
        return ABOUT.strip() + "\nEngine: %s\nKeyboard: %s" % (self.predict.get_version(), self.get_version())

k = Okboard()

if pyotherside:
    pyotherside.atexit(k.close)
