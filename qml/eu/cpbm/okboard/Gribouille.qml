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

    property string last_guess: ""

    property double scaling_ratio: 1

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
            if (pos != expectedPos && pos != expectedPos - 1 && ok) {
                curvepreedit = false;
            }
            update_surrounding()
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
                    curveimpl.learn(result[1], 1);
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
            conf_ok = false;
            show_error("Error loading configuration", true);
        }
    }



    function draw() {
        var ctx = getContext("2d");
        if (blank) {
            ctx.clearRect(0, 0, width, height);

            blank = false;
            return;
        }

        for (var index = 0; index < lastPoints.length; index ++) {
            var crv = lastPoints[index];
            if (crv.length >= 2) {
                ctx.beginPath();
                ctx.strokeStyle = Theme.highlightColor;
                ctx.lineCap = "round";
                ctx.lineWidth = 10; /* slow, removed: * scaling_ratio; */
                ctx.moveTo(crv[0].x, crv[0].y);
                for (var i = 1; i <= crv.length - 1; i ++) {
                    ctx.lineTo(crv[i].x, crv[i].y);
                }
                ctx.stroke();
                ctx.closePath();
                lastPoints[index] = [ crv[crv.length - 1] ];
            }
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
		curveimpl.learn(result, 1); // increase learning count (for user taught words)

		last_guess = result;

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


    function start() {
        perf_timer(undefined)

        cleanupTimer.stop();

        curveimpl.startCurve(); // new API
        started = true;

        start_time = (new Date()).getTime() / 1000;
        curve_length = 0;

        // update configuration if needed
        if (start_time > last_conf_update + 10) {
            last_conf_update = start_time;
            get_config();
        }

        errormsg = ""; // reset any previous error message

	last_guess = "";
    }

    function addPoint(point, index) {
        curveimpl.addPoint(point.x, point.y, index); // new API
        // old API: if (index == 0) { if (lastPoints.length) { curveimpl.addPoint(point.x, point.y); } else { curveimpl.startCurve(point.x, point.y); } }

        while(lastPoints.length <= index) { lastPoints.push([]); }

        if (lastPoints[index].length) {
            var lastPoint = lastPoints[index][lastPoints[index].length - 1];
            curve_length += Math.sqrt(Math.pow(lastPoint.x - point.x, 2) + Math.pow(lastPoint.y - point.y, 2));
        }

        var npt = Object();
        npt.x = point.x;
        npt.y = point.y;
        lastPoints[index].push(npt);

        if (lastPoints[index].length > 3) {
            // draw 3 points at a time (a repaint for each curve point slows down the device too much)
            requestPaint();
        }
    }

    function endCurve(index) {
        curveimpl.endOneCurve(index); // new API
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

        curveimpl.loadKeys(keys);

	scaling_ratio = curveimpl.getScalingRatio();

	if (scaling_ratio <= 0) {
	    show_error("Screen size not supported", true);
	    return;
	}

        log("Keys loaded - count: " + keys.length + " - scaling ratio: " + scaling_ratio);

        keys_ok = true;
    }

    function commitWord(text, replace, correlation_id) {
        // when replace is true, we replace the existing preedit (this is used when the
	// user click on the prediction bar to choose an alternate word)

        // word regexp
        var word_regex = /[a-zA-Z\-\'\u0080-\u023F]+/; // \u0400-\u04FF for cyrillic, and so on ...

        // if preedit is not active, we must directly commit our changes (this happens in Jolla browser URL input field)
        var preedit_ok = (typeof keyboard.inputHandler.preedit != 'undefined');

	// un-learn replaced words
	if (replace) {
	    // learn new word & "unlearn" replaced word
	    if (last_guess) { curveimpl.learn(last_guess, -2 /* because we have juste added 1 */); }
	    curveimpl.learn(text, 1);
	}


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
        var txt;
        var pos = -1;
        if (MInputMethodQuick.surroundingTextValid) {
            txt = MInputMethodQuick.surroundingText;
            pos = MInputMethodQuick.cursorPosition;
        }
        if (pos >= 0) {
            // if surroundingTextValid is true but cursorPosition is -1, Maliit is just bluffing ...

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
                    replaced_word = txt.substr(p1, p2 - p1);

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
        } else {
            // no surroundingText information available: add a trailing space
            // (this seems to be the same behavior as the standard Jolla keyboard when selecting a word in prediction bar)
            // (i don't like it, but it is the "least bad" solution at the moment)
            text = text + ' '
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
            var startpos = params[0];
            var content_old = params[1];
            var content_new = params[2];
            var correlation_id = params[3];
            var capitalize = (startpos == 0);

            var txt = MInputMethodQuick.surroundingText;
            var pos = MInputMethodQuick.cursorPosition;
	    var preedit = keyboard.inputHandler.preedit;
	    log("Backtracking: startpos=" + startpos + " old=" + content_old + " new=" + content_new +
		" context=[" + txt + "] pos=" + pos + " preedit=" + preedit);

	    if (startpos + content_old.length > pos) {
		log("Backtracking failed: result overflows after cursor position")
	    } else if (txt.substr(startpos, content_old.length).toLocaleLowerCase() != content_old.toLocaleLowerCase()) {
		log("Backtracking failed: text does not match [" + content_old + "] != " +
		    "[" + txt.substr(startpos, content_old.length) + "], context: " + txt);
	    } else {
                // current context has expected value: proceed with word replacement
                if (capitalize) {
		    content_new = content_new.substr(0,1).toLocaleUpperCase() + content_new.substr(1);
                }

		log("Backtracking successful: [" + content_old + "] -> [" + content_new + "], context: " + txt)
                MInputMethodQuick.sendCommit(content_new, startpos - pos, content_old.length);
		MInputMethodQuick.sendPreedit(preedit, undefined);
	    }
        }
    }

    function insertSpace() {
        commitWord("", false, undefined);
    }

    function get_predict_words(callback) {
        py.call("okboard.k.get_predict_words", [], callback);
    }

    function show_error(traceback, fatal) {
        /* display error messages to user */
        if (traceback) {
            errormsg = traceback;
            curvepreedit = false;
            curvepreedit = true;
        }

	/* disable swiping in case of unrecoverable error */
	if (fatal) { ok = false; }
    }

}
