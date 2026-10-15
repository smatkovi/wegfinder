#!/usr/bin/env python3
"""Baut die Startsymbole -- beim Bauen, sie liegen nicht im Repo.

    python3 icons/make-icons.py [APK]

* Mit APK (Vorgabe ~/Downloads/wegfinder_26.20.0_APKPure.apk oder $WF_APK)
  und apktool: das Symbol der Android-App aus deren Vektorgrafik (Adaptive
  Icon: ic_launcher_foreground samt Verlauf auf ic_launcher_background,
  sichtbarer Ausschnitt). Das Logo gehoert der iMobility GmbH; deshalb wird
  es nur aus der eigenen APK geholt und nie eingecheckt.
* Ohne APK (oder mit WF_EIGENES=1, so baut das oeffentliche Release): ein
  eigenes Motiv -- ein Weg von einem Punkt zu einer Standortnadel.

Form auf beiden Systemen: die Harmattan-Superellipse |x|^2,8 + |y|^2,8 = 1,
Radius 0,4875 der Kante (an blanco/icon-l-calculator angepasst, wie bei
BioQuiz), vierfach ueberabgetastet.

Ausgabe:
  meego/icons/icon-80.png, icon-64.png      N9/N950
  sailfish/icons/<n>x<n>/wegfinder.png      Sailfish
"""
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
APK = (sys.argv[1] if len(sys.argv) > 1 else
       os.environ.get("WF_APK", os.path.expanduser("~/Downloads/wegfinder_26.20.0_APKPure.apk")))
A = "{http://schemas.android.com/apk/res/android}"

N, R = 2.8, 0.4875
SS = 4


def squircle_maske(g):
    s = g * SS
    c = (s - 1) / 2.0
    yy, xx = np.mgrid[0:s, 0:s]
    r = R * s
    m = ((np.abs(xx - c) / r) ** N + (np.abs(yy - c) / r) ** N <= 1).astype(np.float32)
    m = m.reshape(g, SS, g, SS).mean(axis=(1, 3))
    return Image.fromarray((m * 255).astype(np.uint8), "L")


def farbe(text, farben):
    """Android-Farbwert (#rgb, #argb, #rrggbb, #aarrggbb, @color/x) -> #rrggbb, Deckkraft."""
    text = text.strip()
    if text.startswith("@color/"):
        text = farben.get(text[7:], "#ffffff")
    h = text.lstrip("#")
    if len(h) in (3, 4):
        h = "".join(c * 2 for c in h)
    if len(h) == 8:
        return "#" + h[2:], int(h[:2], 16) / 255.0
    return "#" + h[-6:], 1.0


def logo_aus_apk(ziel_png):
    """Vektor aus der APK -> SVG -> 1024er PNG. False, wenn es nicht geht."""
    if os.environ.get("WF_EIGENES") == "1":
        return False
    if not os.path.isfile(APK) or not shutil.which("apktool") or not shutil.which("rsvg-convert"):
        return False
    with tempfile.TemporaryDirectory() as tmp:
        aus = os.path.join(tmp, "apk")
        r = subprocess.run(["apktool", "d", "-s", "-f", "-o", aus, APK], capture_output=True, text=True)
        res = os.path.join(aus, "res")
        vorder = os.path.join(res, "drawable", "ic_launcher_foreground.xml")
        if r.returncode != 0 or not os.path.isfile(vorder):
            return False
        farben = {}
        for e in ET.parse(os.path.join(res, "values", "colors.xml")).getroot():
            if e.get("name") and e.text:
                farben[e.get("name")] = e.text
        hinter, _ = farbe(farben.get("ic_launcher_background", "#ff4083"), farben)
        wurzel = ET.parse(vorder).getroot()
        vb = float(wurzel.get(A + "viewportWidth"))
        teile, verlaeufe = [], []

        def pfade(knoten, tiefe):
            for k in knoten:
                if k.tag == "group":
                    t = "translate(%s,%s) scale(%s,%s)" % (
                        k.get(A + "translateX", "0"), k.get(A + "translateY", "0"),
                        k.get(A + "scaleX", "1"), k.get(A + "scaleY", "1"))
                    teile.append('<g transform="%s">' % t)
                    pfade(k, tiefe + 1)
                    teile.append("</g>")
                elif k.tag == "path":
                    f = k.get(A + "fillColor", "#ffffff")
                    if f.startswith("@drawable/"):
                        g = ET.parse(os.path.join(res, "drawable", f[10:] + ".xml")).getroot()
                        gid = "v%d" % len(verlaeufe)
                        halte = "".join(
                            '<stop offset="%s" stop-color="%s" stop-opacity="%.3f"/>'
                            % ((i.get(A + "offset"),) + farbe(i.get(A + "color"), farben))
                            for i in g if i.tag == "item")
                        verlaeufe.append(
                            '<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>'
                            % (gid, g.get(A + "startX"), g.get(A + "startY"), g.get(A + "endX"), g.get(A + "endY"), halte))
                        fuellung = "url(#%s)" % gid
                    else:
                        fuellung, deck = farbe(f, farben)
                    teile.append('<path fill="%s" d="%s"/>' % (fuellung, k.get(A + "pathData")))

        pfade(wurzel, 0)
        # Sichtbar ist beim Adaptive Icon die Mitte: 72 von 108 dp.
        rand = vb * 18 / 108.0
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="%f %f %f %f">'
               '<defs>%s</defs><rect x="0" y="0" width="%f" height="%f" fill="%s"/>%s</svg>'
               % (rand, rand, vb - 2 * rand, vb - 2 * rand, "".join(verlaeufe), vb, vb, hinter, "".join(teile)))
        datei = os.path.join(tmp, "logo.svg")
        open(datei, "w").write(svg)
        subprocess.check_call(["rsvg-convert", "-w", "1024", "-h", "1024", datei, "-o", ziel_png])
    return True


def eigenes_logo(ziel_png):
    """Eigenes Motiv: ein geschwungener Weg von einem Punkt zur Nadel, weiss
    auf Blau mit senkrechtem Verlauf wie bei den Harmattan-Symbolen."""
    g = 1024
    oben, unten = np.array((0x2a, 0x9a, 0xe8), np.float32), np.array((0x0c, 0x5c, 0xae), np.float32)
    t = np.linspace(0, 1, g, dtype=np.float32)[:, None, None]
    hg = (oben[None, None, :] * (1 - t) + unten[None, None, :] * t).repeat(g, axis=1)
    bild = Image.fromarray(hg.astype(np.uint8), "RGB").convert("RGBA")

    zeichen = Image.new("RGBA", (g, g), (0, 0, 0, 0))
    d = ImageDraw.Draw(zeichen)
    # Weg als Bezierkurve, gestrichelt
    p0, p1, p2, p3 = (300, 770), (180, 560), (760, 640), (650, 430)
    punkte = []
    for i in range(201):
        u = i / 200.0
        x = (1 - u) ** 3 * p0[0] + 3 * (1 - u) ** 2 * u * p1[0] + 3 * (1 - u) * u * u * p2[0] + u ** 3 * p3[0]
        y = (1 - u) ** 3 * p0[1] + 3 * (1 - u) ** 2 * u * p1[1] + 3 * (1 - u) * u * u * p2[1] + u ** 3 * p3[1]
        punkte.append((x, y))
    laenge, strich, an = 0.0, 0.0, True
    for a, b in zip(punkte, punkte[1:]):
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        strich += seg
        if an:
            d.line([a, b], fill="white", width=34)
            d.ellipse([a[0] - 17, a[1] - 17, a[0] + 17, a[1] + 17], fill="white")
        if strich > (70 if an else 42):
            an, strich = not an, 0.0
    # Startpunkt
    d.ellipse([300 - 62, 770 - 62, 300 + 62, 770 + 62], fill="white")
    d.ellipse([300 - 30, 770 - 30, 300 + 30, 770 + 30], fill=(0x1b, 0x7c, 0xcc, 255))
    # Nadel
    cx, cy, r = 650, 300, 130
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill="white")
    d.polygon([(cx - r * 0.86, cy + r * 0.5), (cx + r * 0.86, cy + r * 0.5), (cx, cy + r * 2.05)], fill="white")
    d.ellipse([cx - 52, cy - 52, cx + 52, cy + 52], fill=(0x1b, 0x7c, 0xcc, 255))
    schatten = zeichen.split()[3].filter(ImageFilter.GaussianBlur(14))
    s = Image.new("RGBA", (g, g), (0, 0, 0, 0))
    s.putalpha(schatten.point(lambda v: v * 0.35))
    bild.alpha_composite(s, (0, 10))
    bild.alpha_composite(zeichen)
    bild.save(ziel_png)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        gross = os.path.join(tmp, "symbol.png")
        if logo_aus_apk(gross):
            print("Symbol: aus der APK (%s)" % APK)
        else:
            eigenes_logo(gross)
            print("Symbol: eigenes")
        quelle = Image.open(gross).convert("RGBA")

        def form(g):
            b = quelle.resize((g, g), Image.LANCZOS)
            b.putalpha(squircle_maske(g))
            return b

        ordner = os.path.join(WURZEL, "meego", "icons")
        os.makedirs(ordner, exist_ok=True)
        form(80).save(os.path.join(ordner, "icon-80.png"))
        form(64).save(os.path.join(ordner, "icon-64.png"))
        for g in (86, 108, 128, 172):
            ziel = os.path.join(WURZEL, "sailfish", "icons", "%dx%d" % (g, g))
            os.makedirs(ziel, exist_ok=True)
            form(g).save(os.path.join(ziel, "wegfinder.png"))


if __name__ == "__main__":
    main()
