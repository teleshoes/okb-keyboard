import QtQuick 2.1
import Sailfish.Silica 1.0
import Sailfish.Email 1.1

/*
  this is obviously very inspired by this example:
  https://github.com/CODeRUS/harbour-mitakuuluu2/blob/master/client/qml/SendLogs.qml
*/

EmailComposerPage {
    id: mailLogs
    objectName: "sendLogs"

    emailTo: "eb@cpbm.eu"
    emailSubject: "OKBoard logs"
    emailBody: "Describe what you were trying to type of what went wrong ..."

    function attach(url, name) {
        attachmentsModel.append({"url": url,
				 "title": name,
				 "mimeType": "application/x-zip-compressed"});
    }
}
