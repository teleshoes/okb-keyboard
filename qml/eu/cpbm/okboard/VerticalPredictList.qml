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
  this file implement the "prediction bar" that shows alternate choices for predicted word
  vertical version for split keyboard
*/

import QtQuick 2.0
import Sailfish.Silica 1.0
import eu.cpbm.okboard 1.0
import com.jolla 1.0

Component {
    Item {
        id: verticalCurvePredictionListView

        SilicaListView {
            id: verticalList

            model: ListModel {
                id: curvePredictionModel
                ListElement {
                    text: "?"
                    error: false
                }
            }

            anchors.fill: parent
            clip: true

            Component.onCompleted: {
                update_model()
            }

	    Connections {
		// update display when curve context changes
		target: keyboard
		onCurvepreeditChanged: { curvePredictionListView.update_model(); }
		onCurveerrorChanged: { curvePredictionListView.update_model(); }
	    }

            Rectangle {
                // visual indication to differentiate okboard candidates vs. standard keyboard completion
                // (not very nice looking at the moment)
                width: parent.width
                height: 2
                color: Theme.highlightColor
            }

            delegate: BackgroundItem {
                onClicked: {
                    if (! error) {
                        console.log("Predition word selected:", text);
                        keyboard.commitWord(text);
                    }
                }
                width: parent.width
                height: geometry.keyHeightLandscape // assuming landscape!

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                    color: highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    fontSizeMode: Text.HorizontalFit
                    textFormat: Text.StyledText
                    text: formatText(model.text)
                    font.bold: model.error
                    font.underline: model.error
                }

                function formatText(text, error) {
                    return text;
                }
            }

            function update_model() {
                if (keyboard.curveerror.length > 0) {
                    curvePredictionModel.clear();
                    curvePredictionModel.append({'text': "Error (see logs)", 'error': true });
                } else {
                    keyboard.get_predict_words(function(result) {
                        curvePredictionModel.clear();
                        if (result && result.length > 0) {
                            curvePredictionModel.append(result);
                        } else {
                            curvePredictionModel.append({ 'text': '<I>No match</I>', 'error': false });
                        }
                    });
                }
            }

        }
    }
}

