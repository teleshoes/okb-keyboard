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
import glob
import subprocess
import zipfile

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
        self.backtrack = self.exception_wrapper(self.predict.backtrack)
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
        self.cptime = 0

        self._cf_cache = dict()

        self.init()
        self.log("okboard.py init complete")

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
                    try: self.log(m, force_log = True)  # Error are logged even if log is disabled
                    except: pass
                self.log()  # flush
                if str(e)[0] == '!': message = str(e)[1:]  # do not append error location for non-error messages
                else: message = "Error in %s: %s (see logs)" % (func.__qualname__, str(e))  # exception for display in GUI
                message += " [click to dismiss]"
                self.last_error = message
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
        self.cpfile = os.path.join(self.config_dir, "okboard.cf")
        _default_conf = os.path.join(os.path.dirname(__file__), "okboard.cf")
        _dist_conf = os.path.join(Okboard.SHARE_PATH, "okboard.cf")
        self.cp = cp = ConfigParser.SafeConfigParser()
        cp.read([ _dist_conf, _default_conf, self.cpfile ])

        # check version
        save = False
        cf_version = 0
        try:
            cf_version = int(cp["main"].get("cf_version", 0)) if "main" in cp else 0
        except: pass

        self.expected_db_version = self.get_expected_db_version()
        self.expected_cf_version = expected_cf_version = self.get_expected_cf_version()
        if expected_cf_version and cf_version != expected_cf_version:
            self.log("Configuration file mismatch: %s != %s" % (cf_version, expected_cf_version))
            # we were using a version with an older data scheme --> reset configuration
            # @todo handle 2 distinct cases: format change (full reset), default curve plugin parameters change (only reset parameter section)
            self.cp = cp = ConfigParser.SafeConfigParser()
            cp.read([ _dist_conf, _default_conf ])
            save = True

        # save if needed
        if not os.path.isfile(self.cpfile): save = True
        for s in [ "main", "default", "portrait", "landscape" ]:
            if s not in cp:  # add sections
                cp[s] = {}
                save = True

        if save:
            if expected_cf_version: cp["main"]["cf_version"] = str(expected_cf_version)
            cp["main"]["verbose"] = cp["main"]["log"] = "1" if test_mode else "0"
            cp["main"]["debug"] = "0"
            with open(self.cpfile, 'w') as f: cp.write(f)

        self.cptime = os.path.getmtime(self.cpfile)
        self.test_mode = test_mode

    def _default_config(self):
        if "log" not in self.cp["main"]: self.cp["main"]["log"] = "0"
        if "debug" not in self.cp["main"]: self.cp["main"]["debug"] = "0"

    def _get_config(self, only_if_modified = False):
        """ return some configuration elements for QML part """
        mtime = os.path.getmtime(self.cpfile) if os.path.isfile(self.cpfile) else 0
        cp = self.cp
        if mtime > self.cptime:
            self.cptime = mtime
            cp.read(self.cpfile)

        # default parameters
        result = dict(config_dir = self.config_dir,
                      local_dir = self.local_dir,
                      log = self.cf("log", 0, mybool),
                      debug = self.cf("debug", 0, mybool),
                      show_wpm = self.cf("show_wpm", 1 if self.test_mode else 0, mybool))

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

    def cf(self, key, default_value = None, cast = None):
        if key in self._cf_cache: return self._cf_cache[key]

        cp = self.cp
        if "main" not in cp: cp["main"] = dict()

        if self.predict.db and self.predict.db.get_param(key):
            ret = self.predict.db.get_param(key)
        elif key in cp["main"]:
            ret = cp["main"][key]
        elif default_value is not None:
            self._default_config()
            ret = default_value
            cp["main"][key] = str(default_value)
            with open(self.cpfile, 'w') as f: cp.write(f)
        else:
            raise Exception("No default value for parameter: %s" % key)

        if cast:
            try:
                ret = cast(ret)
            except:
                cp["main"][key] = str(default_value)
                with open(self.cpfile, 'w') as f: cp.write(f)
                ret = default_value

        self._cf_cache[key] = ret
        return ret

    def set_cf(self, key, value):
        self._cf_cache.pop(key, None)  # remove from cache

        if "main" not in self.cp: self.cp["main"] = dict()
        if key in self.cp["main"] and self.cp["main"][key] == str(value): return
        self.cp["main"][key] = str(value)
        with open(self.cpfile + '.tmp', 'w') as f: self.cp.write(f)
        os.rename(self.cpfile + '.tmp', self.cpfile)

    def set_db(*args): pass  # for compatibility with test tools

    def log(self, *args, **kwargs):
        if not args:
            if self.logf:
                self.logf.write("\n".encode('utf-8'))
                self.logf.close()
                self.logf = None
            return

        force_log = kwargs.get("force_log", False)
        message = ' '.join(map(str, args))

        try: print(message)  # if it fails we'll get the data from the logs
        except: pass

        if self.cf('log', False, mybool) or force_log:
            if not self.logf:
                self.logf = open(os.path.join(self.local_dir, "predict.log"), "ab")
            self.logf.write((message + "\n").encode('utf-8'))
            if force_log:
                self.logf.close()
                self.logf = None

    def _log_qml(self, jsargs):
        txt = ' '.join([ str(x[1]) for x in sorted(jsargs.items(), key = lambda x: int(x[0])) ])
        self.log('QML: ' + txt)

    def _set_context(self, lang, orientation):
        """ sets language and try to load DB """
        self._cf_cache = dict()

        self.lang = lang
        self.orientation = orientation
        new_dbfile = os.path.join(self.local_dir, "predict-%s.db" % lang)
        if new_dbfile and self.predict.db and self.predict.dbfile == new_dbfile:
            pass  # no change, no need to reload
        else:
            self.predict.set_dbfile(new_dbfile)

        if not self.lang or len(self.lang) != 2: return

        # if self.test_mode:
        #     self.predict.load_db()  # no error or version management in test mode
        #     return

        # try to load DB and copy distribution database to user home directory if needed
        message = ""
        init = False
        try:
            if not self.predict.load_db(): init = True

        except Exception as e:
            message = "Corrupted DB: " + str(e)
            init = True

        if not init:
            db_version = int(self.predict.db.get_param("version", 0))
            if self.expected_db_version and db_version != self.expected_db_version:
                message = "!Info: Outdated database (%s/%s) -> User data lost" % (db_version, self.expected_db_version)
                init = True
            else:
                current_db_id = self.predict.db.get_param("id", "0")
                expected_db_id = self.shipped_db_id(self.lang)
                if expected_db_id and current_db_id != expected_db_id:
                    # this is a bit harsh. The keyboard should nicely ask to the user (or upgrade without losing user data)
                    message = "!Info: New database shipped with RPM -> User data lost"
                    init = True

        if init:
            self.predict.close()
            self._reset_db(lang)
            if self._install_dist_db(lang, force = True):
                self.predict.load_db(force_reload = True)

        if message: self.log(message)
        self._logversion()

        # display the message as an error
        if message: raise Exception(message)

    def _reset_db(self, lang):
        self.log("Reseting databases for language %s" % lang)
        remove = [ os.path.join(self.local_dir, "%s.tre" % lang),
                   os.path.join(self.local_dir, "predict-%s.db" % lang),
                   os.path.join(self.local_dir, "predict-%s.ng" % lang) ]
        for fname in remove:
            if os.path.isfile(fname):
                self.log("Removing %s" % fname)
                os.unlink(fname)

    def _install_dist_db(self, lang, force = False):
        ok = False
        for db in [ "predict-%s.db" % lang, "%s.tre" % lang, "predict-%s.ng" % lang ]:
            src = os.path.join(Okboard.SHARE_PATH, db + ".gz")
            dest = os.path.join(self.local_dir, db)
            if os.path.exists(src) and (force or not os.path.exists(dest)):
                self.log("Deploying DB file %s -> %s" % (src, dest))
                with gzip.open(src, 'rb') as rf:
                    with open(dest, 'wb') as wf:
                        shutil.copyfileobj(rf, wf)
                        ok = True

        return ok


    def _cleanup(self, **kwargs):
        # log rotate
        rotate = self.cf("log_rotate", True, mybool)
        self.log()  # flush & close log file
        if rotate:
            logs = [ "curve.log", "predict.log" ]
            rotate_size = max(1, self.cf("rotate_mb", 5, int))
            for log in logs:
                fname = os.path.join(self.local_dir, log)
                if os.path.exists(fname) and os.path.getsize(fname) > rotate_size * 1000000:
                    if log == "predict.log":
                        self._logversion()
                    os.rename(fname, fname + ".bak")

        return self.predict.cleanup(**kwargs)

    def _logversion(self):
        self.log("OKBoard versions: predict=%s keyboard=%s db=%s cf=%s" % (self.predict.get_version(), self.get_version(),
                                                                           self.get_expected_db_version(), self.get_expected_cf_version()))

    def close(self):
        self.log("okboard.py exiting ...")
        self.predict.close()
        self.log()

    def get_expected_db_version(self):
        try:
            with open(os.path.join(os.path.dirname(__file__), "db.version"), "r") as f:
                return int(f.read().strip())
        except: return None

    def get_expected_cf_version(self):
        try:
            with open(os.path.join(os.path.dirname(__file__), "cf.version"), "r") as f:
                return int(f.read().strip())
        except: return None

    def get_version(self):
        try:
            with open(os.path.join(os.path.dirname(__file__), "okboard.version"), "r") as f:
                return f.read().strip()
        except:
            return "unknown"

    def shipped_db_id(self, lang):
        try:
            with open(os.path.join(Okboard.SHARE_PATH, "predict-%s.id" % lang), "r") as f:
                return f.read().strip()
        except: return None

    def reset_all(self):
        self.log("Reseting all databases & settings")
        remove = (glob.glob(os.path.join(self.local_dir, "*.tre")) +
                  glob.glob(os.path.join(self.local_dir, "predict-*.db")) +
                  glob.glob(os.path.join(self.local_dir, "predict-*.ng")) +
                  glob.glob(os.path.join(self.config_dir, "okboard.cf")))
        for fname in remove:
            self.log("Removing %s" % fname)
            os.unlink(fname)

    # --- functions for settings app ---

    def _restart_maliit_server(self):
        # restart maliit server to apply changes
        # (use the right maliit plugin, and reload databases and configuration)
        self.log("Restarting maliit server ...")
        subprocess.call(["killall", "maliit-server"])  # ouch !

    def stg_get_settings(self):
        keyboard_enabled = False
        if os.path.isfile(Okboard.MALIIT_CONF_FILE):
            conf = open(Okboard.MALIIT_CONF_FILE, "r").read()
            if conf.find("okboard") > -1: keyboard_enabled = True

        result = dict(log = self.cf("log", 1, mybool),
                      learn = self.cf("learning_enable", 1, mybool),
                      enable = keyboard_enabled,
                      backtrack = self.cf("backtrack", 1, mybool),
                      show_wpm = self.cf("show_wpm", 1 if self.test_mode else 0, mybool))

        self.log("Settings:", result)
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
        self.log("Settings: set log", value)
        self.set_cf("log", "1" if value else "0")

    def stg_set_learn(self, value):
        self.log("Settings: set learning", value)
        self.set_cf("learning_enable", value is True)

    def stg_set_backtrack(self, value):
        self.log("Settings: set backtracking", value)
        self.set_cf("backtrack", value is True)

    def stg_set_wpm(self, value):
        self.log("Settings: set WPM display", value)
        self.set_cf("show_wpm", value is True)

    def stg_clear_logs(self):
        logs = [ "curve.log", "predict.log" ]
        for log in logs:
            for log2 in [ log, log + '.bak' ]:
                fname = os.path.join(self.local_dir, log2)
                self.log("Removing %s (if present)" % fname)
                if os.path.isfile(fname): os.unlink(fname)
        self._restart_maliit_server()

    def stg_reset_all(self):
        self.reset_all()

        # possible race condition here if keyboard decides to write its configuration again
        self._restart_maliit_server()

    def stg_about(self):
        return ABOUT.strip() + "\nEngine: %s\nKeyboard: %s\nDB format: %s\nConfiguration format: %s" % \
            (self.predict.get_version(), self.get_version(), self.get_expected_db_version(), self.get_expected_cf_version())

    def stg_zip_logs(self):
        zipname = os.path.join(self.local_dir, "okboard-logs.zip")

        logfiles = glob.glob(os.path.join(self.local_dir, "*.log*"))  # also include .log.bak files in case of recent rotation

        self.log("Creating logs zip archive:", zipname, logfiles)

        with zipfile.ZipFile(zipname, "w") as z:
            for logfile in logfiles:
                z.write(logfile, os.path.basename(logfile))

        return [ "file://" + zipname, "okboard-logs.zip" ]

k = Okboard()

if pyotherside:
    pyotherside.atexit(k.close)
