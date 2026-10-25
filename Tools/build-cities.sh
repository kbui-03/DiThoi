#!/bin/bash
# Regenerates the offline city list a typed stop finds its position in.
#   ./Tools/build-cities.sh
#
# The output, DiThoi/Resources/cities.tsv, is committed: the app works with no
# signal, and so does finding Chiang Mai on the map. This script is only how
# the file is remade, the way render-icons.sh remakes the icons.
#
# Source: GeoNames, cities with 15,000 people or more, and the country table.
# CC BY 4.0 (https://www.geonames.org) — which is why the settings screen
# carries a credit line. Remove the line and the licence goes with it.
#
# The file is one header-less line per city:
#   ISO country \t lat \t lon \t population \t name \t other names…
# Names are as GeoNames writes them, diacritics and all; the app folds them.
# "Other names" are only the Latin-script spellings, which is what somebody
# types into a stop: "Saigon" and "Sài Gòn" for Ho Chi Minh City, not every
# script it has ever been written in. Lines starting "#" are countries:
#   # \t ISO \t name
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/cities.zip" https://download.geonames.org/export/dump/cities15000.zip
curl -fsSL -o "$work/countryInfo.txt" https://download.geonames.org/export/dump/countryInfo.txt
unzip -q -o "$work/cities.zip" -d "$work"

mkdir -p DiThoi/Resources
/usr/bin/python3 -I - "$work/cities15000.txt" "$work/countryInfo.txt" DiThoi/Resources/cities.tsv <<'PY'
import sys, unicodedata

cities_path, countries_path, out_path = sys.argv[1:4]

def latin(name):
    folded = unicodedata.normalize("NFKD", name)
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    return folded != "" and all(c.isascii() and (c.isalpha() or c in " -'.") for c in folded)

def key(name):
    folded = unicodedata.normalize("NFKD", name.casefold())
    return "".join(c for c in folded if not unicodedata.combining(c)).strip()

lines = []
for row in open(countries_path, encoding="utf-8"):
    if row.startswith("#"):
        continue
    cols = row.rstrip("\n").split("\t")
    if len(cols) > 4 and cols[0]:
        lines.append(f"#\t{cols[0]}\t{cols[4]}")

cities = []
for row in open(cities_path, encoding="utf-8"):
    cols = row.rstrip("\n").split("\t")
    name, ascii_name, alternates = cols[1], cols[2], cols[3]
    lat, lon, country, population = float(cols[4]), float(cols[5]), cols[8], int(cols[14] or 0)
    seen = {key(name)}
    others = []
    for other in [ascii_name] + alternates.split(","):
        other = other.strip()
        if other and latin(other) and key(other) not in seen and len(other) <= 40:
            seen.add(key(other))
            others.append(other)
    cities.append((country, -population, name,
                   f"{country}\t{lat:.3f}\t{lon:.3f}\t{population}\t" + "\t".join([name] + others)))

cities.sort()
lines += [line for *_, line in cities]
with open(out_path, "w", encoding="utf-8") as out:
    out.write("\n".join(lines) + "\n")
print(f"{len(cities)} cities, {len(lines) - len(cities)} countries → {out_path}")
PY
ls -lh DiThoi/Resources/cities.tsv
