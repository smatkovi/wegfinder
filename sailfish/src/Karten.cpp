#include "Karten.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>

namespace
{
    const char *kPureMapsService = "io.github.rinigus.PureMaps";
    const char *kPureMapsPath = "/io/github/rinigus/PureMaps";
    const char *kPureMapsInterface = "io.github.rinigus.PureMaps";
    const int kActivationTimeoutMs = 30000;
}

Karten::Karten(QObject *parent)
    : QObject(parent)
{
}

bool Karten::pureMapsInstalled() const
{
    return QFile::exists(QStringLiteral("/usr/share/applications/harbour-pure-maps.desktop"))
        || QFile::exists(QStringLiteral("/usr/share/dbus-1/services/io.github.rinigus.PureMaps.service"));
}

QString Karten::gpxPath() const
{
    return QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)
           + QStringLiteral("/wegfinder-fussweg.gpx");
}

void Karten::setMessage(const QString &message)
{
    if (m_lastMessage != message) {
        m_lastMessage = message;
        emit lastMessageChanged();
    }
}

void Karten::zeigeOrt(const QString &title, double latitude, double longitude)
{
    setMessage(QString());
    if (!pureMapsInstalled()) {
        openGeoUri(latitude, longitude);
        return;
    }
    callShowPoi(title, latitude, longitude);
}

void Karten::callShowPoi(const QString &title, double latitude, double longitude)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QLatin1String(kPureMapsService),
                                                      QLatin1String(kPureMapsPath),
                                                      QLatin1String(kPureMapsInterface),
                                                      QStringLiteral("ShowPoi"));
    msg << title << latitude << longitude;
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg, kActivationTimeoutMs);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, latitude, longitude](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (w->isError()) {
                    // e.g. blocked by the sandbox: use the generic geo: handler
                    openGeoUri(latitude, longitude);
                }
            });
}

void Karten::zeigeWeg(const QString &fromName, double fromLat, double fromLon,
                            const QString &toName, double toLat, double toLon,
                            const QVariantList &pointsIn)
{
    setMessage(QString());
    QVariantList points = pointsIn;
    if (points.size() < 2) {
        // No geometry from the server: straight line between the two stops
        points.clear();
        QVariantMap a;
        a.insert(QStringLiteral("lat"), fromLat);
        a.insert(QStringLiteral("lon"), fromLon);
        QVariantMap b;
        b.insert(QStringLiteral("lat"), toLat);
        b.insert(QStringLiteral("lon"), toLon);
        points << a << b;
    }

    if (!pureMapsInstalled()) {
        openGeoUri(toLat, toLon);
        return;
    }

    // Route in the format Pure Maps' navigator understands (same as its GPX router produces)
    QJsonArray xs;
    QJsonArray ys;
    for (const QVariant &v : points) {
        const QVariantMap p = v.toMap();
        xs.append(p.value(QStringLiteral("lon")).toDouble());
        ys.append(p.value(QStringLiteral("lat")).toDouble());
    }
    QJsonObject depart;
    depart.insert(QStringLiteral("x"), xs.first());
    depart.insert(QStringLiteral("y"), ys.first());
    depart.insert(QStringLiteral("icon"), QStringLiteral("depart"));
    depart.insert(QStringLiteral("narrative"), QStringLiteral("Start: %1").arg(fromName));
    QJsonObject arrive;
    arrive.insert(QStringLiteral("x"), xs.last());
    arrive.insert(QStringLiteral("y"), ys.last());
    arrive.insert(QStringLiteral("icon"), QStringLiteral("arrive"));
    arrive.insert(QStringLiteral("narrative"), QStringLiteral("Ziel: %1").arg(toName));
    QJsonObject from;
    from.insert(QStringLiteral("x"), xs.first());
    from.insert(QStringLiteral("y"), ys.first());
    from.insert(QStringLiteral("text"), fromName);
    QJsonObject to;
    to.insert(QStringLiteral("x"), xs.last());
    to.insert(QStringLiteral("y"), ys.last());
    to.insert(QStringLiteral("text"), toName);
    to.insert(QStringLiteral("destination"), true);
    QJsonObject route;
    route.insert(QStringLiteral("x"), xs);
    route.insert(QStringLiteral("y"), ys);
    route.insert(QStringLiteral("maneuvers"), QJsonArray() << depart << arrive);
    route.insert(QStringLiteral("locations"), QJsonArray() << from << to);
    route.insert(QStringLiteral("location_indexes"), QJsonArray() << 0 << (xs.size() - 1));
    route.insert(QStringLiteral("mode"), QStringLiteral("foot"));
    route.insert(QStringLiteral("language"), QStringLiteral("de"));
    route.insert(QStringLiteral("provider"), QStringLiteral("wegfinder"));
    const QString routeJson = QString::fromUtf8(QJsonDocument(route).toJson(QJsonDocument::Compact));

    QDBusMessage msg = QDBusMessage::createMethodCall(QLatin1String(kPureMapsService),
                                                      QLatin1String(kPureMapsPath),
                                                      QLatin1String(kPureMapsInterface),
                                                      QStringLiteral("ShowRoute"));
    msg << routeJson;
    QDBusPendingCall call = QDBusConnection::sessionBus().asyncCall(msg, kActivationTimeoutMs);
    QDBusPendingCallWatcher *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, fromName, toName, toLat, toLon, points](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                if (!w->isError()) {
                    setMessage(QStringLiteral("Fußweg an Pure Maps übergeben."));
                    return;
                }
                // Stock Pure Maps has no ShowRoute: provide the route as GPX for its
                // GPX router and at least show the destination.
                if (writeGpx(fromName, toName, points)) {
                    setMessage(QStringLiteral("Fußweg als GPX gespeichert: %1 — in Pure Maps unter "
                                              "Routing den Router „GPX“ mit dieser Datei und Typ „Zu Fuß“ wählen, "
                                              "dann „Navigate To“.").arg(gpxPath()));
                } else {
                    setMessage(QStringLiteral("GPX konnte nicht gespeichert werden (Berechtigung „Downloads“?). "
                                              "Es wird nur das Ziel angezeigt."));
                }
                callShowPoi(toName, toLat, toLon);
            });
}

bool Karten::writeGpx(const QString &fromName, const QString &toName, const QVariantList &points)
{
    const QString path = gpxPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        return false;
    }
    QTextStream out(&f);
    out.setCodec("UTF-8");
    const QString title = QStringLiteral("Fußweg %1 → %2").arg(fromName, toName);
    out << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        << "<gpx version=\"1.1\" creator=\"wegfinder\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        << "  <metadata><name>" << title.toHtmlEscaped() << "</name><time>"
        << QDateTime::currentDateTimeUtc().toString(Qt::ISODate) << "</time></metadata>\n";
    const QVariantMap first = points.first().toMap();
    const QVariantMap last = points.last().toMap();
    out << "  <wpt lat=\"" << QString::number(first.value(QStringLiteral("lat")).toDouble(), 'f', 6)
        << "\" lon=\"" << QString::number(first.value(QStringLiteral("lon")).toDouble(), 'f', 6)
        << "\"><name>" << fromName.toHtmlEscaped() << "</name></wpt>\n";
    out << "  <wpt lat=\"" << QString::number(last.value(QStringLiteral("lat")).toDouble(), 'f', 6)
        << "\" lon=\"" << QString::number(last.value(QStringLiteral("lon")).toDouble(), 'f', 6)
        << "\"><name>" << toName.toHtmlEscaped() << "</name></wpt>\n";
    out << "  <rte><name>" << title.toHtmlEscaped() << "</name>\n";
    for (const QVariant &v : points) {
        const QVariantMap p = v.toMap();
        out << "    <rtept lat=\"" << QString::number(p.value(QStringLiteral("lat")).toDouble(), 'f', 6)
            << "\" lon=\"" << QString::number(p.value(QStringLiteral("lon")).toDouble(), 'f', 6) << "\"/>\n";
    }
    out << "  </rte>\n</gpx>\n";
    out.flush();
    f.close();
    return true;
}

void Karten::openGeoUri(double latitude, double longitude)
{
    const QString uri = QStringLiteral("geo:%1,%2")
                            .arg(latitude, 0, 'f', 6)
                            .arg(longitude, 0, 'f', 6);
    if (!QDesktopServices::openUrl(QUrl(uri))) {
        setMessage(QStringLiteral("Keine Karten-App für geo:-Adressen gefunden."));
    }
}
