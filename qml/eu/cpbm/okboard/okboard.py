#! /usr/bin/python3
# -*- coding: utf-8 -*-

""" Technical stuff for okboard: error management, configuration management, logs ... """

try: import pyotherside
except: pyotherside = None

import os
import time
import re
import traceback
import configparser as ConfigParser
import json

from predict import Predict

mybool = lambda x: False if str(x).lower() in [ "0", "false", "no", "off", "" ] else True

class Okboard:
    def __init__(self):
        self.lang = None
        self.predict = Predict(self)
        self.last_conf = dict()
        self.orientation = None
        self.logf = None

        # add error management wrappers
        self.guess = self.exception_wrapper(self.predict.guess)
        self.update_surrounding = self.exception_wrapper(self.predict.update_surrounding)
        self.get_predict_words = self.exception_wrapper(self.predict.get_predict_words)
        self.update_preedit = self.exception_wrapper(self.predict.update_preedit)
        self.cleanup = self.exception_wrapper(self.predict.cleanup)

        self.set_context = self.exception_wrapper(self._set_context)
        self.get_config = self.exception_wrapper(self._get_config)
        self.init = self.exception_wrapper(self._init)

        self.init()
        print("okboard.py init complete")

        print("predict.py exiting ...")

    def exception_wrapper(self, func):
        # this is an ugly wrapper to display exceptions because they do not seem to be handled by pyotherside or lost somewhere in js/qml
        def wrapper(*params, **kwargs):
            try:
                return func(*params, **kwargs)
            except Exception as e:
                for m in [ "Exception in function %s: %s" % (func.__qualname__, e), 
                           traceback.format_exc() ]:
                    print(m)
                    self.log(m)
                raise e
        return wrapper

    def _init(self):
        # init path
        test_mode = os.environ.get("OKBOARD_TEST", None)
        if not test_mode or test_mode.lower() in [ "0", "false" ]:
            # production mode
            self.config_dir = os.path.join(os.path.expanduser('~'), ".config/okboard")
            self.local_dir = os.path.join(os.path.expanduser('~'), ".local/share/okboard")
            if not os.path.isdir(self.config_dir): os.makedirs(self.config_dir)
            if not os.path.isdir(self.local_dir): os.makedirs(self.local_dir)
        else:
            # test mode
            self.config_dir = self.local_dir = "/tmp"
            print("Test mode (working directory=%s)" % self.config_dir)

        # config files
        self.cp = cp = ConfigParser.SafeConfigParser()
        self.cpfile = os.path.join(self.config_dir, "okboard.cf")
        _default_conf = os.path.join(os.path.dirname(__file__), "okboard.cf")
        cp.read([ _default_conf, self.cpfile ])

        save = not os.path.isfile(self.cpfile)
        for s in [ "main", "default", "portrait", "landscape" ]:
            if s not in cp:
                cp[s] = {}
                save = True

        if save:
            cp["main"]["log"] = "1" if test_mode else "0"
            cp["main"]["debug"] = "0"
            with open(self.cpfile, 'w') as f: cp.write(f)

        self.cptime = os.path.getmtime(self.cpfile)

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

        # @TODO copier la base la première fois : .db & .tre

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

        if cast: ret = cast(ret)
        return ret

    def log(self, *args):
        message = ' '.join(map(str, args))
        if not args:
            if self.logf:
                self.logf.write("\n")
                self.logf.close()
                self.logf = None
            return
        print(message)
        if self.cf('log', False, mybool):
            if not self.logf:
                self.logf = open(os.path.join(self.local_dir, "predict.log"), "a")
            self.logf.write(message + "\n")

    def _set_context(self, lang, orientation):
        """ sets language and try to load DB """
        self.lang = lang
        self.orientation = orientation
        new_dbfile = os.path.join(self.local_dir, "predict-%s.db" % lang)
        if new_dbfile and self.predict.db and self.predict.dbfile == new_dbfile:
            pass  # no change, no need to reload
        else:
            self.predict.set_dbfile(new_dbfile)

        self.predict.load_db()

    def close():
        print("okboard.py exiting ...")
        self.predict.close()


k = Okboard()

if pyotherside:
    pyotherside.atexit(k.close)
