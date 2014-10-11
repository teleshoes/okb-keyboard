#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <QGuiApplication>
#include <QQuickView>

#include <sailfishapp.h>

#include <stdlib.h>
#include <unistd.h>

#define QML_PATH "/usr/share/maliit/plugins"

int main(int argc, char *argv[])
{
    QGuiApplication *app = SailfishApp::application(argc, argv);

    QQuickView *view = SailfishApp::createView();

    if (! getenv("OKBOARD_TEST")) {
      // in test mode, this program must be run from qml directory
      if (chdir(QML_PATH)) { perror("chdir"); exit(1); }
    }
    view->setSource(QUrl("eu/cpbm/okboard/Settings.qml"));

    view->showFullScreen();
    return app->exec();
}
