#ifndef DIENST_H
#define DIENST_H

// Die Verbindung der Oberflaeche zum Rust-Dienst.
//
// Der Dienst (wf-dienst, Rust) ist ein Kindprozess, kein Server: er liest
// Anfragen zeilenweise von stdin und schreibt Antworten zeilenweise nach
// stdout. Schliesst die App, schliesst sich stdin, und der Dienst beendet
// sich von selbst. Uebernommen aus wienzufuss (regiojet-meego); dieselbe Datei baut auch
// die Sailfish-Fassung (Qt 5).
//
// Eine Zeile hat drei Felder, durch Tabulatoren getrennt:
//
//   hin:     <id> TAB <befehl> TAB <json>
//   zurueck: <id> TAB <1|0>    TAB <json oder Fehlertext als JSON-String>
//
// serde_json schreibt kompakt und maskiert Steuerzeichen in Zeichenketten,
// ein rohes TAB oder Zeilenende kommt im JSON also nie vor. Deshalb genuegt
// es hier, an den ersten zwei Tabulatoren zu teilen -- das JSON selbst
// zerlegt erst die QML-Seite, die die Antwort angefordert hat, und nur die.

#include <QByteArray>
#include <QObject>
#include <QProcess>
#include <QSet>
#include <QString>

class Dienst : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool laeuft READ laeuft NOTIFY laeuftChanged)

public:
    explicit Dienst(const QString &programm, QObject *parent = 0);
    ~Dienst();

    bool laeuft() const;

    // Schickt eine Anfrage und gibt ihre Nummer zurueck. Die Antwort kommt
    // ueber antwort(); die Seite erkennt ihre an der Nummer. werte ist der
    // Text, den JSON.stringify auf der QML-Seite liefert.
    Q_INVOKABLE int anfrage(const QString &befehl, const QString &werte);

    // Adresse im Browser oder Datei in ihrer App oeffnen (PDF, Zahlungsseite).
    Q_INVOKABLE bool oeffnen(const QString &adresse);
    Q_INVOKABLE void kopieren(const QString &text);

signals:
    void antwort(int id, bool ok, const QString &daten);
    void laeuftChanged();

private slots:
    void lesen();
    void fehlerLesen();
    void beendet(int code, QProcess::ExitStatus status);

private:
    void starten();
    void ausstehendeAbbrechen(const QString &grund);

    QString m_programm;
    QProcess *m_prozess;
    QByteArray m_puffer;
    int m_naechste;
    QSet<int> m_ausstehend;
};

#endif
