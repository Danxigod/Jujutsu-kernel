#!/usr/bin/env python3
"""analyze-log.py - resume el log del monitor (oc-release/logs/monitor_juego.log).

    python analyze-log.py [log]

Resume: rango de temperatura, frecuencias de CPU y GPU vistas, escalon de voltaje
de la GPU (vopp 0 = riel mas alto), eventos de throttle y ventana de temps altas.
"""

import re
import sys
from collections import Counter, defaultdict


def num(v):
    m = re.match(r"([\d.]+)", v or "")
    return float(m.group(1)) if m else None


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "oc-release/logs/monitor_juego.log"
    rows = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = re.sub(r"\x1b\[[0-9;]*m", "", line).rstrip()
        if not re.match(r"^\d\d:\d\d:\d\d ", line):
            continue
        p = line.split()
        if len(p) < 9:
            continue
        rows.append(p)

    if not rows:
        print("sin muestras en", path)
        return 0

    print("muestras: %d  (%s -> %s)" % (len(rows), rows[0][0], rows[-1][0]))

    cpu = [num(r[1]) for r in rows]
    gpu = [num(r[4]) for r in rows]
    vopp = [num(r[5]) for r in rows]
    temp = [num(r[6]) for r in rows]
    vcore = [num(r[7]) for r in rows]
    throttles = [r for r in rows if r[8] not in ("-", "?", "")]

    print("CPU big (MHz) : %s" % sorted(set(int(x) for x in cpu if x)))
    print("GPU (MHz)     : %s" % sorted(set(int(x) for x in gpu if x)))
    print("vcore opp     : %s   (0 = riel mas alto)" % sorted(set(int(x) for x in vopp if x)))
    print("riel VCORE mV : %s" % sorted(set(int(x) for x in vcore if x)))

    t = [x for x in temp if x]
    if t:
        print("temp CPU      : min %.1f  max %.1f  media %.1f  ultima %.1f"
              % (min(t), max(t), sum(t) / len(t), t[-1]))
        over = [x for x in t if x >= 85]
        print("  muestras >= 85 C: %d (%.0f%%)" % (len(over), 100.0 * len(over) / len(t)))

    # GPU y escalon de voltaje emparejados (mismo volcado => sin carrera)
    pairs = defaultdict(Counter)
    for r in rows:
        g, v = num(r[4]), num(r[5])
        if g is not None and v is not None:
            pairs[int(g)][int(v)] += 1
    print("GPU -> escalon vcore (vopp):")
    for g in sorted(pairs):
        print("  %4d MHz -> %s" % (g, dict(pairs[g])))

    print("eventos de throttle: %d" % len(throttles))
    for r in throttles[-8:]:
        print("   %s  %s" % (r[0], r[8]))

    print("ultimas 10 muestras:")
    for r in rows[-10:]:
        print("  %s cpu=%s gpu=%s vopp=%s temp=%s rail=%s th=%s" % (r[0], r[1], r[4], r[5], r[6], r[7], r[8]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
