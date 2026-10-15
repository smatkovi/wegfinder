// Ersatz fuer libmeegoextrasplugin.so, nur fuer den Probelauf am Rechner.
//
// Die Harmattan-Extras (Datums- und Zeitwaehler, InfoBanner) sind QML bis
// auf ein kleines Plugin, und das gibt es nur fuer ARM. Es registriert den
// Typ DateTime (nur der Aufzaehlungen wegen) und setzt die
// Kontexteigenschaft "dateTime" mit ein paar Kalenderhilfen -- genau das
// bildet dieser Ersatz nach (Namen aus plugins.qmltypes des Sysroots).
//
// Ohne ihn griffe "import com.nokia.extras" am Rechner auf die
// Symbian-Extras des SDK, und die stellen das Fenster auf 360x640 um.

#include <QDate>
#include <QDeclarativeContext>
#include <QDeclarativeEngine>
#include <QDeclarativeExtensionPlugin>
#include <QObject>
#include <QString>
#include <qdeclarative.h>

class MDateTimeHelper : public QObject
{
    Q_OBJECT
    Q_ENUMS(TimeUnit HourMode)
public:
    enum TimeUnit { Hours = 1, Minutes = 2, Seconds = 4, All = 7 };
    enum HourMode { TwelveHours = 1, TwentyFourHours = 2 };

    explicit MDateTimeHelper(QObject *parent = 0) : QObject(parent) {}

    Q_INVOKABLE QString shortMonthName(int monat) { return QDate::shortMonthName(monat); }
    Q_INVOKABLE bool isLeapYear(int jahr) { return QDate::isLeapYear(jahr); }
    Q_INVOKABLE int daysInMonth(int jahr, int monat) { return QDate(jahr, monat, 1).daysInMonth(); }
    Q_INVOKABLE int currentYear() { return QDate::currentDate().year(); }
    Q_INVOKABLE QString amText() { return QLatin1String("AM"); }
    Q_INVOKABLE QString pmText() { return QLatin1String("PM"); }
    Q_INVOKABLE int hourMode() { return TwentyFourHours; }
};

class ExtrasErsatz : public QDeclarativeExtensionPlugin
{
    Q_OBJECT
public:
    void registerTypes(const char *uri)
    {
        qmlRegisterUncreatableType<MDateTimeHelper>(uri, 1, 0, "DateTime", QLatin1String("nur Aufzaehlungen"));
        qmlRegisterUncreatableType<MDateTimeHelper>(uri, 1, 1, "DateTime", QLatin1String("nur Aufzaehlungen"));
    }
    void initializeEngine(QDeclarativeEngine *engine, const char *)
    {
        engine->rootContext()->setContextProperty(QLatin1String("dateTime"), new MDateTimeHelper(engine));
    }
};

Q_EXPORT_PLUGIN2(meegoextrasplugin, ExtrasErsatz)

#include "extras-ersatz.moc"
