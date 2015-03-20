/*
Copyright (c) 2014, Eric Berenguier <eb@cpbm.eu>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

The views and conclusions contained in the software and documentation are those
of the authors and should not be interpreted as representing official policies,
either expressed or implied, of the FreeBSD Project.
*/

/*
  This file implement all "curve typing" stuff
*/

import QtQuick 2.0
import Sailfish.Silica 1.0
import eu.cpbm.okboard 1.0
import io.thp.pyotherside 1.0

Canvas {
    id: curve
    anchors.fill: parent
    onPaint: { draw(); }

    property bool blank: false
    property string layout: "0"
    property int orientation: -1
    property bool ok: false

    property bool curvepreedit: false
    property int  expectedPos

    property int count: 0
    property var lastPoints

    property string config_dir: ""
    property string local_dir: ""
    property bool conf_ok: true

    property int correlation_id: 0
    property int last_conf_update: 0
    property bool keys_ok: false
    property bool started: false

    property double start_time;
    property double curve_length;
    property double speed;

    property string errormsg: ""

    property bool orientation_disable: false

    property double timer_last;
    property string timer_str;

    property double last_commit: 0;
    property int backtrack_timeout: 0;

    property bool last_capitalize1: false;
    property bool last_capitalize2: false;


    CurveKB {
        id: curveimpl
        onMatchingDone: { matching_done(candidates); }
    }

    Component.onCompleted: {
        lastPoints = []
    }

    Python {
        id: py
        onError: { py.call("okboard.k.get_last_error", [], function(result) { show_error(result); }) }
    }

    Connections {
        // Track changes to surrounding text (for text prediction learning)
        target: MInputMethodQuick
        onCursorPositionChanged: {
            var pos = MInputMethodQuick.cursorPosition;
            if (pos != expectedPos && pos != expectedPos - 1) {
                curvepreedit = false;
            }
        }
        onSurroundingTextChanged: {
            update_surrounding()
        }
    }

    Timer {
        id: cleanupTimer
        interval: 30000
        onTriggered: { cleanup(); }
    }

    function update_surrounding() {
        if (MInputMethodQuick.surroundingTextValid) {
            py.call("okboard.k.update_surrounding", [ MInputMethodQuick.surroundingText, MInputMethodQuick.cursorPosition ], function(result) {
                if (result) {
                    // we get some information about typed word -> send them to curve plugin
                    curveimpl.learn(result[0], result[1]);
                }
            } )
        } else {
            py.call("okboard.k.update_surrounding", [ "", -1 ])
        }
    }

    Connections {
        // Track changes to preedit buffer
        target: keyboard
        onPreeditChanged: {
            py.call("okboard.k.update_preedit", [ keyboard.preedit ])
        }
    }

    function perf_timer(name) {
        var d = new Date()
        var now = d.getTime()
        if (name) {
            timer_str += " " + name + "=" + (now - timer_last)
        } else {
            timer_str = "Perf> " + d.toLocaleTimeString() + " [" + (now % 1000) + "]"
        }
        timer_last = now
    }

    function log() {
        py.call("okboard.k.log_qml", [ arguments ]);
    }

    function init_python() {
        // init uses synchronous call, because we are called very early (loadKeys) and need the python parts initialized
        py.addImportPath(Qt.resolvedUrl('.'));

        py.importModule_sync('okboard');
        log('imported python module');

        // synchronous call because configuration is needed during initialization. Following calls will be asynchronous
        var result = py.call_sync("okboard.k.get_config", [])
        apply_configuration(result)
        log('configuration OK');

        update_surrounding()
    }

    function apply_configuration(conf) {
        if (conf && conf["unchanged"]) {
            // no configuration change

        } else if (conf) {
            log("configuration updated:")
            var msg = "> ";
            for (var k in conf) {
                if (conf.hasOwnProperty(k)) {
                    if (msg.length + conf[k].length > 80) { log(msg); msg = "> "; }
                    msg += " " + k + "=" + conf[k];
                }
            }
            log(msg);

            // path
            config_dir = conf['config_dir'];
            local_dir = conf['local_dir'];

            // log
            var logfile = (conf['log'])?local_dir + "/curve.log":"";
            curveimpl.setLogFile(logfile);

            // debug
            curveimpl.setDebug(conf['debug']);

            // curve matching plugin parameters
            curveimpl.loadParameters(conf['curve_params']);

            // backtracking
            backtrack_timeout = conf['backtrack_timeout'] || 3;

            conf_ok = true;
            orientation_disable =  conf['disable']

        } else {
            // @todo display error message
            log("Error loading configuration");
            conf_ok = false;
            ok = false; // curve typing is disabled
        }
    }



    function draw() {
        var ctx = getContext("2d");
        if (blank) {
            ctx.clearRect(0, 0, width, height);

            blank = false;
            return;
        }

        if (lastPoints.length >= 2) {
            ctx.beginPath();
            ctx.strokeStyle = Theme.highlightColor;
            ctx.lineCap = "round";
            ctx.lineWidth = 10;
            ctx.moveTo(lastPoints[0][0], lastPoints[0][1]);
            for (var i = 1; i <= lastPoints.length - 1; i ++) {
                ctx.lineTo(lastPoints[i][0], lastPoints[i][1]);
            }
            ctx.stroke();
            ctx.closePath();
            lastPoints = [ lastPoints[lastPoints.length - 1] ]
        }
    }

    function reset() {
        if (started) {
            blank = true;
            requestPaint();
            started = false
        }
        lastPoints = [];
    }

    function done(register) {
        perf_timer("draw")
        if (register) {
            var end_time = (new Date()).getTime() / 1000;

            speed = curve_length / (end_time - start_time)
            curveimpl.endCurveAsync(++ correlation_id); // we'll get a signal when curve matching
        } else {
            curveimpl.resetCurve();
        }
        reset();
        cleanupTimer.start();
        perf_timer("reset")
    }

    function matching_done(candidates) {
        // callback on curve matching completed
        perf_timer("curve_match")

        // improve the result with word prediction
        py.call("okboard.k.guess", [ candidates, correlation_id, speed ], function(result) {
            perf_timer("predict")
            if (result && result.length > 0) {
                commitWord(result, false, correlation_id);
            }
        })

    }

    function cleanup() {
        // post processing / cleanup
        py.call("okboard.k.cleanup", [], function(result) {
            if (result) { cleanupTimer.start(); }
        })
    }

    function get_config() {
        py.call("okboard.k.get_config", [ true ], function(result) { apply_configuration(result); })
    }


    function start(point) {
        perf_timer(undefined)

        cleanupTimer.stop();

        lastPoints.push([point.x, point.y]);
        curveimpl.startCurve(point.x, point.y);
        started = true

        start_time = (new Date()).getTime() / 1000;
        curve_length = 0

        // update configuration if needed
        if (start_time > last_conf_update + 10) {
            last_conf_update = start_time;
            get_config()
        }

        errormsg = ""  // reset any previous error message
    }

    function addPoint(point) {
        var lastPoint = lastPoints[lastPoints.length - 1]
        curve_length += Math.sqrt(Math.pow(lastPoint[0] - point.x, 2) + Math.pow(lastPoint[1] - point.y, 2))

        curveimpl.addPoint(point.x, point.y);
        lastPoints.push([point.x, point.y]);

        count += 1;
        if (count >= 3) {
            // draw 3 points at a time (a repaint for each curve point slows down the device too much)
            requestPaint();
            count = 0;
        }
    }

    function updateContext(layout, mode) {
        if (! local_dir) { init_python(); }

        var dir = Qt.resolvedUrl('.');
        if (dir.substr(0,7) == 'file://') {
            dir = dir.substr(7);
        }

        var _get_config = false;

        // update layout
        if (layout.substr(-4) == ".qml") {
            layout = layout.substr(0, layout.length - 4);
        }
        if (layout != curve.layout) {
            _get_config = true;
        }

        // update prediction language & orientation
        if ((typeof MInputMethodQuick.appOrientation !== 'undefined') && (MInputMethodQuick.appOrientation != orientation)) {
            orientation = MInputMethodQuick.appOrientation;
            _get_config = true; // we must read back configuration to get orientation-dependant variables

            keys_ok = false; // must reload keys position
        }

        log("updateContext: layout =", layout, "orientation =", orientation, "mode =", mode, "get_config =", _get_config)

        if (mode && mode != "common") { // sometimes mode is undefined
            // we don't handle "number" or "phone" keyboards
            curve.ok = false;
            return;
        }

        var now = (new Date()).getTime() / 1000;
        if (now > start_time + 300) {
            // this will cause a DB refresh
            log("Waking up after inactivity ...");
            py.call("okboard.k.wake_up", [])
            _get_config = true;
            start_time = now;
        }

        py.call("okboard.k.set_context", [ layout, orientation ]);  // this triggers predict db loading
        if (_get_config) {
            py.call("okboard.k.get_config", [ true ], function(result) {
                apply_configuration(result);
                if (orientation_disable) {
                    curve.ok = false;
                    curve.layout = "--";

                } else if (layout != curve.layout) {
                    var filename = local_dir + "/" + layout + ".tre";
                    log("Loading word tree: " + filename);
                    curve.ok = curveimpl.loadTree(filename);
                    curve.layout = layout;

                    keys_ok = false; // must reload keys position
                }
            })
        }

    }

    function loadKeys(keys) {
        if (! keys) { return; }

        curveimpl.loadKeys(keys)
        log("Keys loaded - count:", keys.length)

        keys_ok = true
    }

    function commitWord(text, replace, correlation_id) {
        // when replace is true, we replace the existing preedit (this is used when the user click on the prediction bar to choose an alternate word)

        // word regexp
        var word_regex = /[a-zA-Z\-\'\u0080-\u023F]+/; // \u0400-\u04FF for cyrillic, and so on ...

        // if preedit is not active, we must directly commit our changes (this happens in Jolla browser URL input field)
        var preedit_ok = (typeof keyboard.inputHandler.preedit != 'undefined');

        // Commit existing Xt9* handle preedits
        if ((! replace) && preedit_ok && keyboard.inputHandler.preedit.length > 0) {
            MInputMethodQuick.sendCommit(keyboard.inputHandler.preedit);
            keyboard.inputHandler.preedit = "";
            keyboard.autocaps = false;
        }

        var rpl_start = 0;
        var rpl_len = 0;
        var replaced_word = "";
        var sentence_delimiter = ".?!";

        // Processing based on surrounding text
        var forceAutocaps = false;
        if (MInputMethodQuick.surroundingTextValid) {
            var txt = MInputMethodQuick.surroundingText;
            var pos = MInputMethodQuick.cursorPosition;

            // handle curve typing inside a word to replace it
            if (pos < txt.length && word_regex.test(txt[pos]) && ! replace) {
                if (pos > 0 && word_regex.test(txt[pos - 1])) {
                    // if user click on a word and then swipe a word, the whole word is replaced
                    var p1 = pos;
                    while (p1 > 0 && word_regex.test(txt[p1 - 1])) { p1 --; }
                    var p2 = pos;
                    while (p2 < txt.length && word_regex.test(txt[p2])) { p2 ++; }
                    rpl_start = p1 - pos;
                    rpl_len = p2 - p1;
                    replaced_word = txt.substr(p1, p2);

                    // handle autocaps in replacements
                    while (p1 > 0 && txt[p1 - 1] == ' ') { p1 --; }
                    if ((p1 > 0 && (sentence_delimiter.indexOf(txt[p1 - 1]) >= 0)) || (p1 == 0)) {
                        forceAutocaps = true;
                    }
                } else {
                    // swiping from the start of a word will insert the new word just before
                    // and added space will be added and committed right now (see below)
                    replace = true
                    text = text + ' '
                    // user will need to backspace to convert back the word as preedit
                }

            } else if (pos > 0) { // Add a space if needed
                var lastc = txt.substr(pos - 1, 1);
                if (lastc != ' ' && lastc != '-' && lastc != '\'') { MInputMethodQuick.sendCommit(' '); }
                if (".?!".indexOf(lastc) >= 0) { forceAutocaps = true; }
            }
        }


        // Add new word as preedit
        if (text.length > 0) {

            // Auto-capitalize
            last_capitalize2 = last_capitalize1;
            last_capitalize1 = false;
            if (keyboard.autocaps || forceAutocaps) {
                text = text.substr(0,1).toLocaleUpperCase() + text.substr(1);
                last_capitalize1 = true;
            }

            if (replace) {
                var old = keyboard.inputHandler.preedit;
                MInputMethodQuick.sendCommit(text);
                if (preedit_ok) {
                    MInputMethodQuick.sendPreedit("", undefined);
                    keyboard.inputHandler.preedit = "";
                }
                py.call("okboard.k.replace_word", [ old, text ]);
            } else {
                if (rpl_len) {
                    if (preedit_ok) {
                        MInputMethodQuick.sendPreedit(text, undefined, rpl_start, rpl_len);
                    } else {
                        MInputMethodQuick.sendCommit(text, rpl_start, rpl_len);
                    }
                    py.call("okboard.k.replace_word", [ replaced_word, text ]);
                } else {
                    if (preedit_ok) {
                        MInputMethodQuick.sendPreedit(text, undefined);
                    } else {
                        MInputMethodQuick.sendCommit(text);
                    }
                }
                keyboard.inputHandler.preedit = text;
            }

            curvepreedit = false // ugly hack :) (force a "onCompleted" on the word prediction list)
            curvepreedit = ! replace;
            expectedPos = MInputMethodQuick.cursorPosition;
        }

        perf_timer("commit_done");
        log(timer_str);

        // start backtracking processing
        if ((text.length == 0) || replace || (! MInputMethodQuick.surroundingTextValid)) {
            last_commit = 0;
            return;
        }

        var now = (new Date()).getTime() / 1000;
        if (backtrack_timeout && now - last_commit < backtrack_timeout) {
            py.call("okboard.k.backtrack", [ correlation_id ], function(params) { backtracking_done(params); });
        }
        last_commit = now
    }

    function backtracking_done(params) {
        if (params && params.length) {
            var w1_new = params[0];
            var w2_new = params[1];
            var w1_old = params[2];
            var w2_old = params[3];
            var correlation_id = params[4];
            var capitalize = /* params[5]; */ last_capitalize2;

            var txt = MInputMethodQuick.surroundingText;
            var pos = MInputMethodQuick.cursorPosition;

            var startpos = txt.length - w1_old.length - 1;
            if (txt.substr(startpos) == w1_old + ' ' && keyboard.preedit == w2_old) {
                // current context has expected value: proceed with word replacement

                log("backtracking OK:", w1_old, w2_old, "->", w1_new, w2_new);

                // replace word 1 as normal text
                if (capitalize) {
                    w1_new = w1_new.substr(0,1).toLocaleUpperCase() + w1_new.substr(1);
                }
                MInputMethodQuick.sendCommit(w1_new + " ", startpos - pos, w1_old.length + 1);

                // replace word 2 as preedit (at least we can easily correct this one)
                MInputMethodQuick.sendPreedit(w2_new, undefined);
                keyboard.inputHandler.preedit = w2_new;
            } else {
                log("backtracking FAILED:", txt, "does not match", w1_old, w2_old);
            }
        }
    }

    function insertSpace() {
        commitWord("", false, undefined);
    }

    function get_predict_words(callback) {
        py.call("okboard.k.get_predict_words", [], callback);
    }

    function show_error(traceback) {
        /* some erreur happened in python or c++ libraries -> notify user */
        if (traceback) {
            errormsg = traceback;
            curvepreedit = false;
            curvepreedit = true;
        }
    }

}
