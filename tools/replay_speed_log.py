#!/usr/bin/env python3
"""Replay Dipstick debug speed logs through the city/highway classifier with
different thresholds, to tune TripClassifier against real drives.

Mirrors TripClassifier.classify (half-mile stretches; highway when the
stretch averages >= avg_mph and never drops below min_mph). Uses the logged
per-step miles instead of coordinates.

    python3 tools/replay_speed_log.py private/speed-*.csv
    python3 tools/replay_speed_log.py --avg 40 --min 25 private/speed-*.csv
"""
import argparse
import csv

def classify(rows, avg_mph, min_mph, segment=0.5, max_accuracy=50.0, max_gap=30.0):
    city = highway = 0.0
    miles = seconds = 0.0
    low = float("inf")

    def close():
        nonlocal city, highway, miles, seconds, low
        if miles > 0:
            average = miles / (seconds / 3600) if seconds > 0 else 0
            if average >= avg_mph and low >= min_mph:
                highway += miles
            else:
                city += miles
        miles = seconds = 0.0
        low = float("inf")

    usable = [r for r in rows if 0 <= float(r["accuracy_m"]) <= max_accuracy]
    # step_miles in the log is from the previous *logged* sample; when samples
    # are dropped for accuracy, sum the steps across the dropped ones.
    pending = 0.0
    prev_t = None
    for r in rows:
        pending += float(r["step_miles"])
        if not (0 <= float(r["accuracy_m"]) <= max_accuracy):
            continue
        t = float(r["seconds"])
        if prev_t is None:
            prev_t, pending = t, 0.0
            continue
        dt = t - prev_t
        step, pending = pending, 0.0
        prev_t = t
        if dt <= 0 or dt > max_gap:
            close()
            continue
        speed = float(r["speed_mph"])
        mph = speed if speed >= 0 else step / (dt / 3600)
        miles += step
        seconds += dt
        low = min(low, mph)
        if miles >= segment:
            close()
    close()
    return city, highway

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+")
    parser.add_argument("--avg", type=float, help="highway average mph (default: try 40, 45)")
    parser.add_argument("--min", type=float, help="highway minimum mph (default: try 20, 25, 30)")
    args = parser.parse_args()
    settings = [(a, m) for a in ([args.avg] if args.avg else [40, 45]) for m in ([args.min] if args.min else [20, 25, 30])]

    for path in args.files:
        with open(path) as f:
            rows = list(csv.DictReader(f))
        print(path)
        for a, m in settings:
            city, hwy = classify(rows, a, m)
            total = city + hwy
            pct = hwy / total * 100 if total else 0
            print(f"  avg>={a:>4.0f} min>={m:>3.0f}:  {total:6.2f} mi  {pct:5.1f}% highway  ({city:.2f} city / {hwy:.2f} hwy)")

if __name__ == "__main__":
    main()
