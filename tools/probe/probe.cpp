// Probelauf der N9-Oberflaeche am Rechner, ohne Telefon und ohne Fenster.
//
// Laedt meego/qml/main.qml in Qt 4.8 (X11-Bau aus dem QtSDK) mit den
// Desktop-Harmattan-Komponenten und haengt den echten Netzdienst (am
// Rechner gebaut, gegen den echten Server) als "Dienst" an.
// Dann arbeitet es eine Liste von Schritten ab:
//
//   warte:MS        Ereignisschleife MS Millisekunden laufen lassen
//   js:AUSDRUCK     im Kontext von main.qml auswerten (ids sind sichtbar)
//   bild:DATEI.png  das Fenster als Bild ablegen
//
// Uebernommen aus wienzufuss (regiojet-meego), gestartet von tools/probe.sh.

#include <QApplication>
#include <QDeclarativeContext>
#include <QDeclarativeEngine>
#include <QDeclarativeExpression>
#include <QDeclarativeItem>
#include <QDeclarativeView>
#include <QEventLoop>
#include <QPixmap>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <cstdio>

#include "src/Dienst.h"


static void warten(int ms)
{
    QEventLoop schleife;
    QTimer::singleShot(ms, &schleife, SLOT(quit()));
    schleife.exec();
}

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    const QStringList args = app.arguments();
    if (args.size() < 3) {
        std::fprintf(stderr, "probe DIENST MAIN.QML [schritte...]\n");
        return 2;
    }
    Dienst dienst(args.at(1));
    QDeclarativeView view;
    view.setAttribute(Qt::WA_DontShowOnScreen);
    view.engine()->rootContext()->setContextProperty(QLatin1String("Dienst"), &dienst);
    view.setResizeMode(QDeclarativeView::SizeRootObjectToView);
    view.resize(480, 854);
    view.setSource(QUrl::fromLocalFile(args.at(2)));
    view.show();
    warten(800);
    if (!view.errors().isEmpty() || !view.rootObject()) {
        for (int i = 0; i < view.errors().size(); ++i)
            std::fprintf(stderr, "probe: QML-Fehler: %s\n", qPrintable(view.errors().at(i).toString()));
        return 1;
    }
    QDeclarativeContext *kontext = QDeclarativeEngine::contextForObject(view.rootObject());

    for (int i = 3; i < args.size(); ++i) {
        const QString s = args.at(i);
        if (s.startsWith(QLatin1String("warte:"))) {
            warten(s.mid(6).toInt());
        } else if (s.startsWith(QLatin1String("js:"))) {
            QDeclarativeExpression ausdruck(kontext, view.rootObject(), s.mid(3));
            const QVariant wert = ausdruck.evaluate();
            if (ausdruck.hasError())
                std::fprintf(stderr, "probe: js-Fehler: %s\n", qPrintable(ausdruck.error().toString()));
            else if (wert.isValid())
                std::printf("probe: %s => %s\n", qPrintable(s.mid(3, 60)), qPrintable(wert.toString()));
            warten(50);
        } else if (s.startsWith(QLatin1String("bild:"))) {
            warten(100);
            QPixmap::grabWidget(&view).save(s.mid(5));
            std::printf("probe: Bild %s\n", qPrintable(s.mid(5)));
        }
    }
    return 0;
}

#include "probe.moc"
