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
*/

import QtQuick 2.0
import Sailfish.Silica 1.0
import eu.cpbm.okboard 1.0
import com.jolla 1.0

Component {
    TopItem {
        SilicaListView {
            id: curvePredictionListView

            model: ListModel {
                id: curvePredictionModel
                ListElement {
                    text: "?"
                    error: false
                }
            }

            Component {
                id: uselessHeader
                BackgroundItem {
                    height: parent.height
                    width: headerLabel.width + 2 * Theme.paddingMedium
		    // width: wpm.width + 2 * Theme.paddingMedium

                    Image {
			visible: keyboard.wpm == 0
                        id: headerLabel
                        anchors.centerIn: parent
                        source: "pen.png"
			height: 20 * keyboard.scaling_ratio;
			width: 20 * keyboard.scaling_ratio;
                        // unicode characters did not show on all devices, so we
                        // replace it with an image (unfortunately, it does not
                        // use theme colors)
		    }
		    Text {
			visible: keyboard.wpm > 0
			width: parent.width // QTBUG-30896
			id: wpm
			horizontalAlignment: Text.AlignHCenter // does not work ???
			color: Theme.primaryColor
			font { pixelSize: Theme.fontSizeTiny; family: Theme.fontFamily }
			text: "WPM\n" + keyboard.wpm
			anchors.centerIn: parent
			font.bold: true
		    }
                }
            }


            Component.onCompleted: {
                curvePredictionListView.update_model()
            }

	    Connections {
		// update display when curve context changes

		target: keyboard
		onCurvepreeditChanged: { curvePredictionListView.update_model(); }
		onCurveerrorChanged: { curvePredictionListView.update_model(); }
	    }

            orientation: ListView.Horizontal
            anchors.fill: parent
            header: uselessHeader
            boundsBehavior: Flickable.StopAtBounds


            delegate: BackgroundItem {
                onClicked: {
                    if (error) {
			keyboard.clearError();
		    } else {
                        console.log("Predition word selected:", text);
                        keyboard.commitWord(text);
                    }
                }
                width: candidateText.width + Theme.paddingLarge
                height: parent ? parent.height : 0

                Text {
                    id: candidateText
                    anchors.centerIn: parent
                    color: Theme.primaryColor // Theme.highlightColor
                    font { pixelSize: Theme.fontSizeSmall; family: Theme.fontFamily }
                    text: formatText(model.text, model.error)
                    font.bold: model.error
                    font.underline: model.error

                    function formatText(text, error) {
                        return text;
                    }
                }
            }

            function update_model() {
                if (keyboard.curveerror.length > 0) {
                    curvePredictionModel.clear();
                    var message = keyboard.curveerror.replace(/\n.*$/, '')
                    curvePredictionModel.append({'text': message, 'error': true });
                } else {
                    keyboard.get_predict_words(function(result) {
                        curvePredictionModel.clear();
                        if (result && result.length > 0) {
                            curvePredictionModel.append(result);
                        } else {
                            curvePredictionModel.append({ 'text': '<I>No match found</I>', 'error': false });
                        }
                    });
                }
            }

        }
    }
}
