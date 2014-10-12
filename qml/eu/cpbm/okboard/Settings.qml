import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.0

ApplicationWindow {
    id: app

    property bool kb_enabled: false
    property bool pref_log: false
    property bool pref_learn: false

    Python {
        id: py
    }

    Component.onCompleted: {
        py.addImportPath(Qt.resolvedUrl('.'));

        py.importModule('okboard', function(result) {
            console.log('imported python module');

            py.call("okboard.k.stg_get_settings", [ ], function(result) {
                pref_log = result["log"]
                pref_learn = result["learn"]
                app.kb_enabled = result["enable"]
                console.log("Settings OK")
            })
        })
    }

    function set_kb_enable(value) {
        kb_enabled = value
        py.call("okboard.k.stg_enable", [ value ]);

    }

    cover: CoverBackground {
        Column {
            anchors.centerIn: parent
            Label {
                color: Theme.primaryColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                anchors.horizontalCenter: parent.horizontalCenter
                text: "OKboard"
            }
            Label {
                color: Theme.highlightColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                anchors.horizontalCenter: parent.horizontalCenter
                text: kb_enabled?"Enabled":"Disabled"
            }
        }

        CoverActionList {
            iconBackground: true

            CoverAction {
                iconSource: "image://theme/icon-cover-next"
                onTriggered: {
                    set_kb_enable(! app.kb_enabled)
                }
            }
        }

    }

    initialPage: Component {
        Page {
            id: page


            SilicaFlickable {
                id: settings
                contentHeight: column.height
                contentWidth: parent.width
                anchors.fill: parent

                VerticalScrollDecorator { flickable: settings }

                RemorsePopup {
                    id: remorse
                }

                Column {
                    id: column
                    spacing: Theme.paddingLarge
                    width: parent.width

                    PageHeader {
                        title: "OKboard settings"
                    }

                    SectionHeader {
                        text: "Keyboard selection"
                    }

                    TextSwitch {
                        id: st_enable
                        checked: app.kb_enabled
                        text: "Enable OKBoard (aka Magic Keyboard)"
                        description: "OKBoard replaces the default Jolla keyboard. Just uncheck this item to go back to the Jolla keyboard. When switching keyboards, the new one may be unavailable for a few seconds"
                        automaticCheck: false
                        onClicked: {
                            /* remorse.execute((checked?"Disable":"Enable") + " OKboard", function() {  */
                            set_kb_enable(! checked)
                            /* }) */
                        }
                    }

                    SectionHeader {
                        text: "Settings"
                    }

                    TextSwitch {
                        id: st_log
                        text: "Enable logs"
                        automaticCheck: true
                        checked: app.pref_log
                        description: "Logs are automatically rotated from time to time"
                        onCheckedChanged: {
                            app.pref_log = st_log.checked
                            py.call("okboard.k.stg_set_log", [ st_log.checked ]);
                        }
                    }

                    TextSwitch {
                        id: st_learn
                        text: "Enable learning"
                        automaticCheck: true
                        checked: app.pref_learn
                        description: "If disabled, the keyboard continue to collect statistics but they are not used to improve accuracy"
                        onCheckedChanged: {
                            app.pref_learn = st_learn.checked
                            py.call("okboard.k.stg_set_learn", [ st_learn.checked ]);
                        }
                    }

                    SectionHeader {
                        text: "Administration"
                    }

                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Clear logs"
                        onPressed: {
                            remorse.execute("Clear logs", function() { py.call("okboard.k.stg_clear_logs", [ ]); } )
                        }
                    }

                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Reset all databases & settings"
                        onPressed: {
                            remorse.execute("Reset DB & settings", function() { py.call("okboard.k.stg_reset_all", [ ]); } )
                        }
                    }

                }

            }

        }
    }
}
