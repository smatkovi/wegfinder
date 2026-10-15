#!/usr/bin/env python3
"""Spielt den Dienst einmal komplett gegen den echten Server durch.

    python3 tools/dienst-probe.py /pfad/zu/wf-dienst [HOME]

Suche -> Routen (samt weiterer Verkehrsmittel) -> Karte -> Abfahrten ->
Fahrtverlauf -> Umgebung -> Kachel. Zeigt je Schritt Dauer, Groesse und
einen Ausschnitt der Antwort; endet mit Fehlercode, wenn etwas scheitert.
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

prog = sys.argv[1]
heim = sys.argv[2] if len(sys.argv) > 2 else "/tmp/wfheim"
os.makedirs(heim, exist_ok=True)
p = subprocess.Popen([prog], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                     stderr=open(os.path.join(heim, "probe.log"), "w"),
                     env=dict(os.environ, HOME=heim), text=True, bufsize=1)
nr = 0
fehler = 0


def frage(befehl, werte=None, zeigen=300):
    global nr, fehler
    nr += 1
    t = time.time()
    p.stdin.write("%d\t%s\t%s\n" % (nr, befehl, json.dumps(werte or {})))
    p.stdin.flush()
    zeile = p.stdout.readline().rstrip("\n")
    i, ok, daten = zeile.split("\t", 2)
    v = json.loads(daten)
    print("== %-14s %s %5d ms %6d B  %s" % (befehl, "ok" if ok == "1" else "FEHLER",
                                          (time.time() - t) * 1000, len(daten), daten[:zeigen]))
    if ok != "1":
        fehler += 1
    return v if ok == "1" else None


frage("start")
a = frage("suche", {"text": "Wien Westbahnhof"})[0]
b = frage("suche", {"text": "Stephansplatz"})[0]
r = frage("routen", {"von": a, "nach": b}, 200)
for g in r["gruppen"]:
    print("   Gruppe %s (%s): %d Routen" % (g["titel"], g["schluessel"], len(g["routen"])))
    for x in g["routen"][:3]:
        print("     %s %s-%s %s %s | %s" % (x["titel"], x["ab"].get("zeit"), x["an"].get("zeit"), x["dauer"],
                                         x["untertitel"], ", ".join(l["text"] for l in x["linien"])))
for u in r["offen"]:
    w = frage("routen_url", {"url": u}, 120)
    for g in (w or {}).get("gruppen", []):
        for x in g["routen"]:
            print("     [%s] %s %s %s %s" % (g["schluessel"], x["titel"], x["anbieter"], x["dauer"], x["untertitel"]))
spaeter = r["gruppen"][0]["spaeter"]
if spaeter:
    frage("routen_url", {"url": spaeter}, 120)
rid = r["gruppen"][0]["routen"][0]["id"]
k = frage("karte", {"route": rid}, 200)
print("   Linien %d, Punkte %d, Marker %d" % (len(k["linien"]), sum(len(l["punkte"]) for l in k["linien"]),
                                           len(k["marker"])))
d = frage("abfahrten", {"station": a["id"], "max": 20}, 200)
for x in d["abfahrten"][:5]:
    print("     %s %s %s -> %s Gl.%s %s" % (x["zeit"], x["live"], x["linie"], x["richtung"], x["gleis"], x["art"]))
frage("abfahrten", {"station": a["id"], "max": 20}, 80)  # aus dem Zwischenspeicher
f = frage("fahrt", {"url": d["abfahrten"][0]["fahrt"]}, 200)
print("   Halte %d, aktuell %s, Linie %d Punkte" % (len(f["halte"]), f["aktuell"], len(f["linie"])))
u = frage("umgebung", {"n": 48.201, "s": 48.192, "w": 16.330, "o": 16.345, "zoom": 16, "filter": ""}, 200)
print("   Punkte %d, Gruppen %s" % (len(u["punkte"]), u["gruppen"]))
frage("ort_merken", {"ort": a}, 100)
frage("ort_merken", {"ort": b, "favorit": True, "bezeichnung": "Stephansdom"}, 100)
frage("verbindung_merken", {"von": a, "nach": b}, 100)
o = frage("orte", {}, 300)
port = frage("kacheln")["port"]
t = time.time()
png = urllib.request.urlopen("http://127.0.0.1:%d/14/8936/5681.png" % port).read()
print("== kachel         %5d ms %6d B  PNG=%s" % ((time.time() - t) * 1000, len(png), png[:4] == b"\x89PNG"))
t = time.time()
png = urllib.request.urlopen("http://127.0.0.1:%d/14/8936/5681.png" % port).read()
print("== kachel (Cache) %5d ms %6d B" % ((time.time() - t) * 1000, len(png)))
frage("speicher")
p.stdin.close()
p.wait()
print("FEHLER: %d" % fehler)
sys.exit(1 if fehler else 0)
