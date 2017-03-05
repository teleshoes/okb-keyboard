import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.0

ApplicationWindow {
    id: app

    property bool kb_enabled: false
    property bool pref_log: false
    property bool pref_learn: false
    property bool pref_backtrack: false
    property bool pref_wpm: false
    property string about: "?"

    Python {
        id: py
    }

    Component.onCompleted: {
        py.addImportPath(Qt.resolvedUrl('.'));

        py.importModule('okboard', function(result) {
            console.log('imported python module');

            py.call("okboard.k.stg_get_settings", [ ], function(result) {
                pref_log = result["log"];
                pref_learn = result["learn"];
		pref_backtrack = result["backtrack"];
		pref_wpm = result["show_wpm"];
                app.kb_enabled = result["enable"];
                console.log("Settings OK");

                py.call("okboard.k.stg_about", [ ], function(result) {
                    app.about = result;
                })

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
                    set_kb_enable(! app.kb_enabled);
                }
            }
        }

    }

    initialPage: Component {
        Page {
            id: page

            allowedOrientations: Orientation.All

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
                        description: "Logs can be found in ~/.local/share/okboard/ (all *.log and *.log.bak files). They are automatically rotated from time to time"
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

		    TextSwitch {
			id: st_backtrack
                        text: "Enable backtracking"
                        automaticCheck: true
                        checked: app.pref_backtrack
                        description: "Correct past mistakes in the current sentence if they become obvious when there is more context available. This is only activated if you continually swipe words. If you take a break between words, it is assumed you will do needed changes manually"
                        onCheckedChanged: {
                            app.pref_backtrack = st_backtrack.checked;
                            py.call("okboard.k.stg_set_backtrack", [ st_backtrack.checked ]);
                        }
                    }

		    TextSwitch {
			id: st_wpm
                        text: "Show typing speed"
                        automaticCheck: true
                        checked: app.pref_wpm
                        description: "Show typing speed as WPM (Words Per Minute)"
                        onCheckedChanged: {
                            app.pref_wpm = st_wpm.checked;
                            py.call("okboard.k.stg_set_wpm", [ st_wpm.checked ]);
                        }
                    }


                    SectionHeader {
                        text: "Feedback"
                    }

                    Button {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Send logs by e-mail"
			enabled: app.pref_log && app.kb_enabled
                        onPressed: {
			    py.call("okboard.k.stg_check_logs", [ ], function(result) {
				if (result) {
				    var dialog = pageStack.push(Qt.resolvedUrl("MailLogs.qml"));
				    py.call("okboard.k.stg_zip_logs", [ ], function(result) {
					dialog.attach(result[0], result[1]);
				    });
				} else {
				    // No logs
				    py.call("okboard.k.popup", [ "Can not send report", "Maybe logs are missing or empty" ]);
				}
			    });
                        }
                    }

                    Text {
			width: column.width * 0.8
                        color: Theme.secondaryColor
                        font.family: Theme.fontFamily
			font.pixelSize: Theme.fontSizeTiny
                        text: "Send recent logs to OKBoard team in order to help investigate issues or for debugging.\nYou must first activate logs, then reproduce any issue you want to report and then use this function.\nYou can change destination address if you want to check what information is really sent."
			wrapMode: Text.WordWrap
			anchors.horizontalCenter: parent.horizontalCenter
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

                    SectionHeader {
                        text: "About"
                    }

                    Label {
                        color: Theme.secondaryColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeTiny
                        text: app.about
                    }

                }

            }

        }
    }
}
