#include "Dienst.h"

#include <QtGlobal>
#if QT_VERSION >= 0x050000
#include <QGuiApplication>
#define WF_APP QGuiApplication
#else
#include <QApplication>
#define WF_APP QApplication
#endif
#include <QClipboard>
#include <QDesktopServices>
#include <QStringList>
#include <QUrl>
#include <cstdio>

Dienst::Dienst(const QString &programm, QObject *parent)
    : QObject(parent), m_programm(programm), m_prozess(0), m_naechste(1)
{
    starten();
}

Dienst::~Dienst()
{
    if (m_prozess) {
        // stdin zu ist das Zeichen zum Aufhoeren; der Dienst beendet sich
        // dann selbst. Nur wer nicht hoert, wird beendet.
        m_prozess->disconnect(this);
        m_prozess->closeWriteChannel();
        if (!m_prozess->waitForFinished(1500)) {
            m_prozess->kill();
            m_prozess->waitForFinished(500);
        }
    }
}

bool Dienst::laeuft() const
{
    // Auch "Starting" zaehlt: direkt nach start() -- und bis die
    // Ereignisschleife das erste Mal laeuft -- steht der Prozess noch nicht
    // auf Running. Wer das als "tot" las, startete den Dienst bei jeder
    // weiteren Anfrage neu, und alle vorher geschickten Anfragen gingen mit
    // dem alten Prozess verloren: von mehreren Anfragen beim Oeffnen einer
    // Seite kam nur die letzte an. Geschrieben werden darf schon im Zustand
    // Starting; QProcess puffert, bis die Leitung steht.
    return m_prozess && m_prozess->state() != QProcess::NotRunning;
}

void Dienst::starten()
{
    if (m_prozess) {
        m_prozess->disconnect(this);
        m_prozess->deleteLater();
    }
    m_puffer.clear();
    m_prozess = new QProcess(this);
    connect(m_prozess, SIGNAL(readyReadStandardOutput()), this, SLOT(lesen()));
    connect(m_prozess, SIGNAL(readyReadStandardError()), this, SLOT(fehlerLesen()));
    connect(m_prozess, SIGNAL(finished(int,QProcess::ExitStatus)),
            this, SLOT(beendet(int,QProcess::ExitStatus)));
    m_prozess->start(m_programm, QStringList(), QIODevice::ReadWrite);
    emit laeuftChanged();
}

int Dienst::anfrage(const QString &befehl, const QString &werte)
{
    if (!laeuft())
        starten();
    const int id = m_naechste++;
    QByteArray zeile = QByteArray::number(id);
    zeile += '\t';
    zeile += befehl.toUtf8();
    zeile += '\t';
    // Ein Zeilenende im Text haette die Zeile geteilt. JSON.stringify
    // maskiert es zwar, aber die Absicherung kostet nichts.
    QByteArray json = werte.isEmpty() ? QByteArray("{}") : werte.toUtf8();
    json.replace('\n', ' ');
    zeile += json;
    zeile += '\n';
    m_ausstehend.insert(id);
    m_prozess->write(zeile);
    return id;
}

void Dienst::lesen()
{
    m_puffer += m_prozess->readAllStandardOutput();
    int ende;
    while ((ende = m_puffer.indexOf('\n')) >= 0) {
        const QByteArray zeile = m_puffer.left(ende);
        m_puffer.remove(0, ende + 1);
        const int t1 = zeile.indexOf('\t');
        const int t2 = t1 < 0 ? -1 : zeile.indexOf('\t', t1 + 1);
        if (t2 < 0) {
            std::fprintf(stderr, "dienst: unlesbare Zeile: %s\n", zeile.left(120).constData());
            continue;
        }
        bool zahl = false;
        const int id = zeile.left(t1).toInt(&zahl);
        if (!zahl)
            continue;
        const bool ok = zeile.mid(t1 + 1, t2 - t1 - 1) == "1";
        m_ausstehend.remove(id);
        emit antwort(id, ok, QString::fromUtf8(zeile.constData() + t2 + 1, zeile.size() - t2 - 1));
    }
}

void Dienst::fehlerLesen()
{
    // Das Protokoll des Dienstes durchreichen: wer die App per ssh startet,
    // sieht es so im selben Fenster.
    const QByteArray text = m_prozess->readAllStandardError();
    std::fwrite(text.constData(), 1, text.size(), stderr);
    std::fflush(stderr);
}

void Dienst::beendet(int code, QProcess::ExitStatus status)
{
    std::fprintf(stderr, "dienst: beendet (code %d, %s)\n", code,
                 status == QProcess::CrashExit ? "abgestuerzt" : "normal");
    ausstehendeAbbrechen(QString::fromUtf8("Der Netzdienst wurde unerwartet beendet."));
    emit laeuftChanged();
    // Neu gestartet wird bei der naechsten Anfrage, nicht hier -- sonst
    // liefe ein Dienst, der sofort abstuerzt, in einer Schleife.
}

void Dienst::ausstehendeAbbrechen(const QString &grund)
{
    const QList<int> ids = m_ausstehend.toList();
    m_ausstehend.clear();
    QString json = grund;
    json.replace(QLatin1String("\\"), QLatin1String("\\\\"));
    json.replace(QLatin1String("\""), QLatin1String("\\\""));
    json = QLatin1String("\"") + json + QLatin1String("\"");
    for (int i = 0; i < ids.size(); ++i)
        emit antwort(ids.at(i), false, json);
}

bool Dienst::oeffnen(const QString &adresse)
{
    const QUrl url = adresse.startsWith(QLatin1Char('/'))
            ? QUrl::fromLocalFile(adresse) : QUrl(adresse);
    return QDesktopServices::openUrl(url);
}

void Dienst::kopieren(const QString &text)
{
    WF_APP::clipboard()->setText(text);
}
