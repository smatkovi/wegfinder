#ifndef KARTEN_H
#define KARTEN_H

#include <QObject>
#include <QString>
#include <QVariantList>

// Uebergibt Ziele und Fusswege an eine Karten-App -- aus Fahrplan AT
// (src/maplauncher.*) uebernommen.
//
// Hands locations and walking routes over to a map application.
//
// Pure Maps is addressed via its D-Bus interface (io.github.rinigus.PureMaps,
// auto-started by D-Bus activation). A complete route is passed with the
// ShowRoute method that the patch in contrib/ adds to Pure Maps; without that
// patch the route is written as GPX (~/Downloads) for Pure Maps' GPX router and only the
// destination is shown. Any other geo: handler is used as last resort.
class Karten : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool pureMapsDa READ pureMapsInstalled CONSTANT)
    Q_PROPERTY(QString meldung READ lastMessage NOTIFY lastMessageChanged)
    Q_PROPERTY(QString gpxPath READ gpxPath CONSTANT)

public:
    explicit Karten(QObject *parent = 0);

    bool pureMapsInstalled() const;
    QString lastMessage() const { return m_lastMessage; }
    QString gpxPath() const;

    Q_INVOKABLE void zeigeOrt(const QString &title, double latitude, double longitude);

    // points: list of {lat, lon} maps in walking order (may be empty -> straight line)
    Q_INVOKABLE void zeigeWeg(const QString &fromName, double fromLat, double fromLon,
                               const QString &toName, double toLat, double toLon,
                               const QVariantList &points);

signals:
    void lastMessageChanged();

private:
    void setMessage(const QString &message);
    void openGeoUri(double latitude, double longitude);
    void callShowPoi(const QString &title, double latitude, double longitude);
    bool writeGpx(const QString &fromName, const QString &toName, const QVariantList &points);

    QString m_lastMessage;
};

#endif // KARTEN_H
