import QtQuick 2.0
import Sailfish.Silica 1.0
import io.thp.pyotherside 1.0

ApplicationWindow {
    id: app

    property bool kb_enabled: false
    
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
    }
    initialPage: Component {
        Page {
            id: page
            
            Python {
                id: py
            }
            
            Component.onCompleted: {
                py.addImportPath(Qt.resolvedUrl('.'));
                
                py.importModule('okboard', function(result) {
                    console.log('imported python module');
                    
                    py.call("okboard.k.stg_get_settings", [ ], function(result) {
                        st_log.checked = result["log"]
                        st_learn.checked = result["learn"]
                        app.kb_enabled = st_enable.checked = result["enable"]
                        console.log("Settings OK")
                    })
                })
            }
            
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
                        text: "Enable OKBoard (aka Magic Keyboard)"
                        description: "It replaces the Jolla keyboard. Just uncheck this item to go back to the default keyboard"
                        automaticCheck: false
                        onClicked: {
                            /* remorse.execute((checked?"Disable":"Enable") + " OKboard", function() {  */
                            checked = ! checked;
                            app.kb_enabled = checked;
                            py.call("okboard.k.stg_enable", [ checked ]);
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
                        description: "Logs are automatically rotated from time to time"
                        onCheckedChanged: { py.call("okboard.k.stg_set_log", [ st_log.checked ]); }
                    }

                    TextSwitch {
                        id: st_learn
                        text: "Enable learning"
                        automaticCheck: true
                        description: "If disabled, the keyboard continue to collect statistics but they are not used to improve accuracy"
                        onCheckedChanged: { py.call("okboard.k.stg_set_learn", [ st_log.checked ]); }
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
