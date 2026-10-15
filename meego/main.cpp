// wegfinder fuer MeeGo Harmattan (Nokia N9/N950).
//
// Die Oberflaeche ist QML 1 mit den Harmattan-Komponenten. Ins Netz geht
// alles ueber wf-dienst (Rust, eigenes OpenSSL -- das Qt 4.7 des Geraets
// kann kein TLS 1.2), auch die Kartenkacheln (ueber 127.0.0.1). QML
// erreicht ihn ueber die Kontexteigenschaft "Dienst" (src/Dienst.h).

#include <QApplication>
#include <QDeclarativeContext>
#include <QDeclarativeEngine>
#include <QDeclarativeView>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QInputContext>
#include <QInputContextFactory>
#include <QStringList>

#include "src/Dienst.h"

// Harmattan schreibt die Adresse des Sitzungsbusses hierhin. Ein per ssh
// gestarteter Prozess erbt sie nicht -- ohne sie erreicht die App den
// Browser nicht (Links auf der Info-Seite).
static void sitzungsBusSetzen()
{
    if (!qgetenv("DBUS_SESSION_BUS_ADDRESS").isEmpty())
        return;
    QFile f(QLatin1String("/tmp/session_bus_address.user"));
    if (!f.open(QIODevice::ReadOnly))
        return;
    const QStringList zeilen = QString::fromLatin1(f.readAll()).split(QLatin1Char('\n'));
    for (int i = 0; i < zeilen.size(); ++i) {
        const QString z = zeilen.at(i);
        const int p = z.indexOf(QLatin1String("DBUS_SESSION_BUS_ADDRESS="));
        if (p < 0)
            continue;
        QString wert = z.mid(p + 25).trimmed();
        if (wert.endsWith(QLatin1Char(';')))
            wert.chop(1);
        if (wert.length() > 1 && (wert.at(0) == QLatin1Char('"') || wert.at(0) == QLatin1Char('\''))
                && wert.at(wert.length() - 1) == wert.at(0))
            wert = wert.mid(1, wert.length() - 2);
        if (!wert.isEmpty())
            qputenv("DBUS_SESSION_BUS_ADDRESS", wert.toLatin1());
        return;
    }
}

int main(int argc, char *argv[])
{
    sitzungsBusSetzen();
    QApplication app(argc, argv);

    // Ohne das bleibt die virtuelle Tastatur weg, sobald die ausziehbare
    // eingeklappt ist (N950): eine nackte QApplication waehlt keinen
    // Eingabekontext.
    if (QInputContext *ic = QInputContextFactory::create(QLatin1String("MInputContext"), &app))
        app.setInputContext(ic);

    app.setApplicationName(QLatin1String("wegfinder"));
    app.setOrganizationName(QLatin1String("wegfinder"));

    // Alles relativ zum Programm: /opt/wegfinder/bin/wegfinder -> /opt/wegfinder
    const QString wurzel = QDir(QFileInfo(QCoreApplication::applicationFilePath())
                                .absolutePath() + QLatin1String("/..")).absolutePath();

    Dienst dienst(wurzel + QLatin1String("/bin/wf-dienst"));

    QDeclarativeView view;
    view.engine()->rootContext()->setContextProperty(QLatin1String("Dienst"), &dienst);
    view.setResizeMode(QDeclarativeView::SizeRootObjectToView);
    view.setSource(QUrl::fromLocalFile(wurzel + QLatin1String("/qml/main.qml")));
    view.showFullScreen();
    return app.exec();
}
