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

    CurveKB {
        id: curveimpl
    }

    Component.onCompleted: {
        lastPoints = []
    }

    Python {
        id: py
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

    function update_surrounding() {
        if (MInputMethodQuick.surroundingTextValid) {
            py.call("okboard.k.update_surrounding", [ MInputMethodQuick.surroundingText, MInputMethodQuick.cursorPosition ])
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

    function init_python() {
        // init uses synchronous call, because we are called very early (loadKeys) and need the python parts initialized
        py.addImportPath(Qt.resolvedUrl('.'));

        py.importModule_sync('okboard');
        console.log('imported python module');
        
        // synchronous call because configuration is needed during initialization. Following calls will be asynchronous
        var result = py.call_sync("okboard.k.get_config", []) 
        apply_configuration(result)
        console.log('configuration OK');

        update_surrounding()
    }

    function apply_configuration(conf) {
        if (conf && conf["unchanged"]) {
            // no configuration change 

        } else if (conf) {
            console.log("configuration updated:")
            var msg = "> ";
            for (var k in conf) {
                if (conf.hasOwnProperty(k)) {
                    if (msg.length + conf[k].length > 80) { console.log(msg); msg = "> "; }
                    msg += " " + k + "=" + conf[k];
                }
            }
            console.log(msg);

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

            conf_ok = true;

        } else {
            // @todo display error message
            console.log("Error loading configuration");
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
        if (register) {
            curveimpl.endCurve(++ correlation_id);

            // get candidate for curve matching
            var candidates = curveimpl.getCandidates();

            // improve the result with word prediction
            py.call("okboard.k.guess", [ candidates, correlation_id ], function(result) {
                if (result && result.length > 0) {
                    commitWord(result, false);
                }
            })

            // post processing / cleanup
            // py.call("okboard.k.cleanup", [])

        }
        reset();
    }

    function get_config() {
        py.call("okboard.k.get_config", [ true ], function(result) { apply_configuration(result); })
    }


    function start(point) {
        lastPoints.push([point.x, point.y]);
        curveimpl.startCurve(point.x, point.y);
        started = true

        // update configuration if needed
        var now = (new Date()).getTime() / 1000;
        if (now > last_conf_update + 10) {
            last_conf_update = now;
            get_config()
        }
    }

    function addPoint(point) {
        curveimpl.addPoint(point.x, point.y);
        lastPoints.push([point.x, point.y]);

        count += 1;
        if (count >= 3) {
            // draw 3 points at a time (a repaint for each curve point slows down the device too much)
            requestPaint();
            count = 0;
        }
    }

    function updateContext(layout) {
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
            /* QQQ
            if (layout.substr(-4) == ".qml") {
                layout = layout.substr(0, layout.length - 4);
            }
            var filename = local_dir + "/" + layout + ".tre";
            console.log("Loading word tree: " + filename);
            curve.ok = curveimpl.loadTree(filename);
            curve.layout = layout;

            keys_ok = false; // must reload keys position
            */
        }

        // update prediction language & orientation
        if ((typeof MInputMethodQuick.appOrientation !== 'undefined') && (MInputMethodQuick.appOrientation != orientation)) {
            orientation = MInputMethodQuick.appOrientation;
            _get_config = true; // we must read back configuration to get orientation-dependant variables

            keys_ok = false; // must reload keys position
        }

        console.log("updateContext: layout =", layout, "orientation =", orientation, "get_config =", _get_config)

        py.call("okboard.k.set_context", [ layout, orientation ]);  // this triggers predict db loading
        if (_get_config) {
            py.call("okboard.k.get_config", [ true ], function(result) { 
                apply_configuration(result); 
                if (layout != curve.layout) {
                    var filename = local_dir + "/" + layout + ".tre";
                    console.log("Loading word tree: " + filename);
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
        console.log("Keys loaded - count:", keys.length)

        keys_ok = true
    }

    function commitWord(text, replace) {
        // when replace is true, we replace the existing preedit (this is used when user click on the prediction bar to choose on alernate word)

        // Commit existing Xt9* handle preedits
        if ((! replace) && keyboard.inputHandler.preedit.length > 0) {
            MInputMethodQuick.sendCommit(keyboard.inputHandler.preedit);
            keyboard.inputHandler.preedit = "";
            keyboard.autocaps = false;
        }

        // Add a space if needed
        var forceAutocaps = false;
        if (MInputMethodQuick.surroundingTextValid) {
            var txt = MInputMethodQuick.surroundingText;
            var pos = MInputMethodQuick.cursorPosition;
            if (pos > 0) {
                var lastc = txt.substr(pos - 1, 1)
                if (lastc != ' ' && lastc != '-' && lastc != '\'') { MInputMethodQuick.sendCommit(' '); }
                if (lastc == '.') { forceAutocaps = true; }
            }
        }

        // Auto-capitalize
        if (keyboard.autocaps || forceAutocaps) {
            text = text.substr(0,1).toLocaleUpperCase() + text.substr(1);
        }

        // Add new word as preedit
        if (text.length > 0) {
            if (replace) {
                var old = keyboard.inputHandler.preedit
                MInputMethodQuick.sendCommit(text)
                MInputMethodQuick.sendPreedit("", undefined);
                keyboard.inputHandler.preedit = "";
                py.call("okboard.k.replace_word", [ old, text ])
            } else {
                MInputMethodQuick.sendPreedit(text, undefined);
                keyboard.inputHandler.preedit = text;
            }
            
            curvepreedit = false // ugly hack :) (force a "onCompleted" on the word prediction list)
            curvepreedit = ! replace;
            expectedPos = MInputMethodQuick.cursorPosition;
        }
    }
    
    function insertSpace() {
        commitWord("", false);
    }

    function get_predict_words(callback) {
        py.call("okboard.k.get_predict_words", [], callback);
    }

}
