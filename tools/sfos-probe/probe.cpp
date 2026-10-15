// Probelauf der Sailfish-Oberflaeche ohne Telefon: im SDK-Ziel unter qemu
// (sb2), ohne Bildschirm (QT_QPA_PLATFORM=minimal). Gezeichnet wird dabei
// nichts -- Qt 5.6 hat ohne OpenGL keinen Szenengraphen --, aber alle
// Seiten werden wirklich erzeugt, und jeder QML-Fehler landet auf stderr.
//
//   probe DIENST QMLDATEI [js:AUSDRUCK | warte:MS]...
//
// Uebernommen aus wienzufuss, gestartet von tools/sfos-probe.sh.
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickItem>
#include <QQuickView>
#include <QEventLoop>
#include <QTimer>
#include <QUrl>
#include <cstdio>

#include "Dienst.h"
#include "Karten.h"

static void warten(int ms)
{
    QEventLoop s;
    QTimer::singleShot(ms, &s, SLOT(quit()));
    s.exec();
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    const QStringList args = app.arguments();
    Dienst dienst(args.at(1));
    Karten karten;
    QQuickView view;
    view.rootContext()->setContextProperty(QStringLiteral("Dienst"), &dienst);
    view.rootContext()->setContextProperty(QStringLiteral("Karten"), &karten);
    view.setSource(QUrl::fromLocalFile(args.at(2)));
    warten(1500);
    QObject *wurzel = view.rootObject();
    if (!wurzel) {
        std::fprintf(stderr, "probe: keine Wurzel\n");
        return 1;
    }
    QQmlContext *kontext = QQmlEngine::contextForObject(wurzel);
    for (int i = 3; i < args.size(); ++i) {
        const QString s = args.at(i);
        if (s.startsWith(QLatin1String("warte:"))) {
            warten(s.mid(6).toInt());
        } else if (s.startsWith(QLatin1String("js:"))) {
            QQmlExpression a(kontext, wurzel, s.mid(3));
            const QVariant w = a.evaluate();
            if (a.hasError())
                std::fprintf(stderr, "probe: js-Fehler: %s\n", qPrintable(a.error().toString()));
            else
                std::printf("probe: %s => %s\n", qPrintable(s.mid(3, 70)), qPrintable(w.toString()));
            std::fflush(stdout);
            warten(50);
        }
    }
    return 0;
}
