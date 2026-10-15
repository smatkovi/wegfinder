// wegfinder fuer Sailfish OS.
//
// Silica-Oberflaeche; ins Netz geht alles ueber wf-dienst (derselbe
// Rust-Dienst wie am N9, statisch gebaut), auch die Kartenkacheln. QML
// erreicht ihn ueber "Dienst" (meego/src/Dienst.h, dieselbe Klasse wie am
// N9); "Karten" uebergibt Ziele und Fusswege an Pure Maps.

#include <QGuiApplication>
#include <QQmlContext>
#include <QQuickView>
#include <QScopedPointer>

#include <sailfishapp.h>

#include "Dienst.h"
#include "Karten.h"

int main(int argc, char *argv[])
{
    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    app->setOrganizationName(QStringLiteral("wegfinder"));
    app->setApplicationName(QStringLiteral("wegfinder"));
    app->setApplicationVersion(QStringLiteral(APP_VERSION));

    Dienst dienst(QStringLiteral(NETZDIENST));
    Karten karten;

    QScopedPointer<QQuickView> view(SailfishApp::createView());
    QQmlContext *ctx = view->rootContext();
    ctx->setContextProperty(QStringLiteral("Dienst"), &dienst);
    ctx->setContextProperty(QStringLiteral("Karten"), &karten);
    view->setSource(SailfishApp::pathTo(QStringLiteral("qml/wegfinder.qml")));
    view->show();
    return app->exec();
}
