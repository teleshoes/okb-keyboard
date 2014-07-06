/*
 * Copyright (C) 2011 Nokia Corporation and/or its subsidiary(-ies). All rights reserved.
 * Copyright (C) 2012-2013 Jolla Ltd.
 *
 * Contact: Pekka Vuorela <pekka.vuorela@jollamobile.com>
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * Redistributions of source code must retain the above copyright notice, this list
 * of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list
 * of conditions and the following disclaimer in the documentation and/or other materials
 * provided with the distribution.
 * Neither the name of Nokia Corporation nor the names of its contributors may be
 * used to endorse or promote products derived from this software without specific
 * prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

import QtQuick 2.0
import com.jolla 1.0
import QtFeedback 5.0
import com.meego.maliitquick 1.0
import org.nemomobile.configuration 1.0
import com.jolla.keyboard 1.0
import Sailfish.Silica 1.0
import com.jolla.keyboard.translations 1.0
import org.nemomobile.dbus 1.0
import eu.cpbm.okboard 1.0

Item {
    id: canvas

    KeyboardGeometry { id: geometry }

    width: MInputMethodQuick.screenWidth
    height: MInputMethodQuick.screenHeight

    property bool portraitRotated: width > height
    property bool portraitLayout: portraitRotated ?
                                      (MInputMethodQuick.appOrientation == 90 || MInputMethodQuick.appOrientation == 270) :
                                      (MInputMethodQuick.appOrientation == 0 || MInputMethodQuick.appOrientation == 180)

    property int activeIndex: -1
    property variant layoutModel: _layoutModel
    property variant layoutRow: _layoutRow

    property Item phraseEngine // for hwr

    Component.onCompleted: {
        activeIndex = Math.max(_layoutModel.getLayoutIndex(layoutConfig.value), 0)
    }

    onPortraitLayoutChanged: keyboard.updateLayoutIfAllowed()

    function updateIMArea() {
        if (!MInputMethodQuick.active)
            return

        var x = 0, y = 0, width = 0, height = 0;
        var angle = MInputMethodQuick.appOrientation

        // column height doesn't instantly change when topItem changes. workaround by calculating height ourselves
        var columnHeight = keyboard.height + (topItem.item ? topItem.item.height : 0)

        switch (angle) {
            case 0:
            y = MInputMethodQuick.screenHeight - columnHeight
            case 180:
            x = (MInputMethodQuick.screenWidth - inputItems.width) / 2
            width = inputItems.width
            height = columnHeight
            break;

            case 270:
            x = MInputMethodQuick.screenWidth - columnHeight
            case 90:
            y = (MInputMethodQuick.screenHeight - inputItems.width) / 2
            width = columnHeight
            height = inputItems.width
            break;
        }

        MInputMethodQuick.setInputMethodArea(Qt.rect(x, y, width, height))
        MInputMethodQuick.setScreenRegion(Qt.rect(x, y, width, height))
    }
    function captureFullScreen() {
        if (!MInputMethodQuick.active)
            return

        MInputMethodQuick.setScreenRegion(Qt.rect(x, y, width, height))
    }
    function saveCurrentLayoutSetting() {
        layoutConfig.value = _layoutModel.get(activeIndex).layout
    }

    InputHandlerManager {
        id: handlerManager
    }

    DBusAdaptor {
        service: "com.jolla.keyboard"
        path: "/com/jolla/keyboard"
        iface: "com.jolla.keyboard"

        signal clearData
        onClearData: {
            console.log("got clear data request from dbus")
            _layoutModel.useHandlers([])
            handlerManager.clearHandlerData()
            _layoutModel.updateInputHandlers()
            keyboard.inputHandler = basicInputHandler // just to make sure
        }
    }


    LayoutModel {
        id: _layoutModel

        property var inputHandlers: new Array

        onEnabledLayoutsChanged: updateInputHandlers()
        Component.onCompleted: updateInputHandlers()

        function updateInputHandlers() {
            var newHandlers = new Array
            var i

            for (i = 0; i < count; ++i) {
                var layout = get(i)
                if (layout.enabled && layout.handler !== "") {
                    newHandlers.push(layout.handler)
                }
            }

            // Hack for handwriting: if handwriting is enabled, enable also pinyin
            if (newHandlers.indexOf("HwrInputHandler.qml") >= 0 && newHandlers.indexOf("Xt9CpInputHandler.qml") == -1) {
                newHandlers.push("Xt9CpInputHandler.qml")
            }

            useHandlers(newHandlers)
        }

        function useHandlers(newHandlers) {
            var oldHandlers = Object.keys(inputHandlers)
            var i

            // delete unusused handlers
            for (i = 0; i < oldHandlers.length; ++i) {
                if (newHandlers.indexOf(oldHandlers[i]) == -1) {
                    var deletable = oldHandlers[i]
                    handlerManager.deleteInstance(inputHandlers[deletable])
                    delete inputHandlers[deletable]

                    if (deletable === "Xt9CpInputHandler.qml") {
                        canvas.phraseEngine = null
                    }
                }
            }

            for (i = 0; i < newHandlers.length; ++i) {
                var handler = newHandlers[i]
                if (inputHandlers[handler] !== undefined) {
                    continue // already exists
                }

                var component = Qt.createComponent("/usr/share/maliit/plugins/com/jolla/" + handler)

                if (component.status === Component.Ready) {
                    // using separate creator so instances can be deleted instantly
                    var object = handlerManager.createInstance(component, canvas)
                    inputHandlers[handler] = object

                    // hack for hwr, if pinyin, make sure it's reachable
                    if (handler === "Xt9CpInputHandler.qml") {
                        canvas.phraseEngine = object
                    }
                } else {
                    console.warn("input handler instantiation failed for " + handler + ": " + component.errorString())
                }
            }
        }
    }

    ConfigurationValue {
        id: layoutConfig

        key: "/sailfish/text_input/active_layout"
        defaultValue: "en.qml"

        onValueChanged: {
            var index = _layoutModel.getLayoutIndex(value)
            if (index >= 0) {
                _layoutRow.switchLayout(index)
            }
        }
    }

    Item {
        // container at the of current orientation. allows actual keyboard to show relative to that.
        id: root

        width: MInputMethodQuick.appOrientation == 0 || MInputMethodQuick.appOrientation == 180
               ? parent.width : parent.height
        height: 1
        transformOrigin: Item.TopLeft
        rotation: MInputMethodQuick.appOrientation
        x: MInputMethodQuick.appOrientation == 180 || MInputMethodQuick.appOrientation == 270
           ? parent.width : 0
        y: MInputMethodQuick.appOrientation == 0 || MInputMethodQuick.appOrientation == 270
           ? parent.height : 0

        onRotationChanged: updateIMArea()

        ThemeEffect {
            id: buttonPressEffect
            effect: ThemeEffect.PressWeak
        }

        Column {
            id: inputItems
            width: keyboard.width
            anchors.bottom: parent.bottom

            onHeightChanged: {
                if (!showAnimation.running) {
                    updateIMArea()
                }
            }

            PredictList {
                id: curvePredictionList
            }

            // FIXME: don't unload item when changing temporarily to basic handler
            Loader {
                id: topItem
                sourceComponent: (keyboard.curvepreedit?curvePredictionList:keyboard.inputHandler.topItem)
                width: parent.width
                visible: item !== null
            }


            CurveKeyboardBase {
                id: keyboard

                property bool allowLayoutChanges
                property string mode: "common"

                property bool fullyOpen
                property bool expandedPaste: true

                width: root.width
                portraitMode: portraitLayout
                layout: mode === "common" ? _layoutRow.layout
                                          : mode === "number" ? (portraitMode ? number_portrait
                                                                              : number_landscape)
                                                              : (portraitMode ? phone_portrait
                                                                              : phone_landscape)
                layoutChangeAllowed: mode === "common"

                onModeChanged: layoutRow.layout.visible = mode === "common"

                function updateLayoutIfAllowed() {
                    if (allowLayoutChanges) {
                        updateLayout()
                    }
                }

                function updateLayout() {
                    var newMode = mode

                    if (MInputMethodQuick.contentType === Maliit.NumberContentType)
                        newMode = "number"
                    else if (MInputMethodQuick.contentType === Maliit.PhoneNumberContentType)
                        newMode = "phone"
                    else
                        newMode = "common"

                    if (newMode !== mode) {
                        inputHandler.active = false
                        mode = newMode
                    }

                    updateInputHandler()
                    keyboard.updateCurveContext()
                }

                function updateInputHandler() {
                    var advancedInputHandler
                    var previousInputHandler = inputHandler

                    var _layout = _layoutRow.layout
                    var handler = layoutModel.get(canvas.activeIndex).handler

                    if (handler !== "" && _layout && (_layout.type !== "" || MInputMethodQuick.predictionEnabled)) {
                        advancedInputHandler =  _layoutModel.inputHandlers[handler]

                        if (advancedInputHandler == undefined) {
                            console.warn("invalid inputhandler for " + handler + ", forcing paste input handler")
                            advancedInputHandler = pasteInputHandler
                        }
                    } else {
                        advancedInputHandler = pasteInputHandler
                    }

                    // update active input handler
                    if (MInputMethodQuick.contentType === Maliit.FreeTextContentType
                            && !MInputMethodQuick.hiddenText) {
                        inputHandler = advancedInputHandler
                    } else if (MInputMethodQuick.contentType === Maliit.NumberContentType
                               || MInputMethodQuick.contentType === Maliit.PhoneNumberContentType) {
                        inputHandler = basicInputHandler
                    } else if (_layout && _layout.type === "hwr") {
                        inputHandler = advancedInputHandler
                    } else {
                        inputHandler = pasteInputHandler
                    }

                    if ((previousInputHandler !== inputHandler) && previousInputHandler) {
                        previousInputHandler.active = false
                    }

                    inputHandler.active = true
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.rgba(Theme.highlightBackgroundColor, .15) }
                        GradientStop { position: 1; color: Theme.rgba(Theme.highlightBackgroundColor, .3) }
                    }
                }
                
                InputHandler {
                    id: basicInputHandler
                }

                PasteInputHandler {
                    id: pasteInputHandler
                }

                NumberLayoutPortrait {
                    id: number_portrait
                    visible: keyboard.mode === "number" && keyboard.portraitMode
                }

                NumberLayoutLandscape {
                    id: number_landscape
                    visible: keyboard.mode === "number" && !keyboard.portraitMode
                }

                PhoneNumberLayoutPortrait {
                    id: phone_portrait
                    visible: keyboard.mode === "phone" && keyboard.portraitMode
                }
                PhoneNumberLayoutLandscape {
                    id: phone_landscape
                    visible: keyboard.mode === "phone" && !keyboard.portraitMode
                }

                LayoutRow {
                    id: _layoutRow
                }

                Connections {
                    target: Clipboard
                    onTextChanged: {
                        if (Clipboard.text) {
                            keyboard.expandedPaste = true
                        }
                    }
                }
            }
        }

        Connections {
            target: MInputMethodQuick
            onActiveChanged: {
                if (MInputMethodQuick.active) {
                    hideAnimation.stop()
                    showAnimation.start()
                } else {
                    showAnimation.stop()
                    hideAnimation.start()
                }
            }
            onContentTypeChanged: keyboard.updateLayoutIfAllowed()
            onHiddenTextChanged: keyboard.updateLayoutIfAllowed()
            onPredictionEnabledChanged: keyboard.updateLayoutIfAllowed()

            onFocusTargetChanged: keyboard.allowLayoutChanges = activeEditor
        }

        SequentialAnimation {
            id: hideAnimation

            ScriptAction {
                script: {
                    MInputMethodQuick.setInputMethodArea(Qt.rect(0, 0, 0, 0))
                    keyboard.fullyOpen = false
                }
            }

            NumberAnimation {
                target: inputItems
                property: "opacity"
                to: 0
                duration: 300
            }

            ScriptAction {
                script: {
                    MInputMethodQuick.setScreenRegion(Qt.rect(0, 0, 0, 0))
                    keyboard.resetKeyboard()
                }
            }
        }

        SequentialAnimation {
            id: showAnimation

            ScriptAction {
                script: {
                    canvas.visible = true // framework currently initially hides. Make sure visible
                    keyboard.updateLayout()
                    areaUpdater.start() // ensure height has updated before sending it
                }
            }

            PauseAnimation { duration: 200 }

            NumberAnimation {
                target: inputItems
                property: "opacity"
                to: 1.0
                duration: 200
            }
            PropertyAction {
                target: keyboard
                property: "fullyOpen"
                value: true
            }
        }

        Timer {
            id: areaUpdater
            interval: 1
            onTriggered: canvas.updateIMArea()
        }
        Component.onCompleted: {
            MInputMethodQuick.actionKeyOverride.setDefaultIcon("image://theme/icon-m-enter")
            MInputMethodQuick.actionKeyOverride.setDefaultLabel("")
        }
    }
}

