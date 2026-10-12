#!/bin/bash
# Renders DiThoi/Assets.xcassets/AppIcon.appiconset from Shared/TripMark.swift.
#   ./Tools/render-icons.sh
#
# The PNGs and Contents.json are both generated from one slot table, so they
# cannot disagree with each other. What they *can* disagree with is the asset
# compiler, which is why this script does not stop at "the files were written".
set -euo pipefail
cd "$(dirname "$0")/.."

out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

xcrun swiftc -O -parse-as-library \
  Shared/TripMark.swift Tools/RenderIcons.swift \
  -o "$out/rendericons"
"$out/rendericons" DiThoi/Assets.xcassets/AppIcon.appiconset

# actool is the reason the default appearance carries the three optical cuts
# while dark and tinted are one 1024 each: a per-size child that also carries an
# `appearances` key is *dropped*, with a warning that reads like a stray-file
# notice ("the app icon set has 16 unassigned children") and an exit code of 0.
# So the check is on the renditions that came out the other side, not on the
# exit code — and it runs every time, so the day Apple fixes it is the day this
# says so and the table above can grow.
echo "— compiling the catalogue —"
compiled="$out/compiled"
mkdir -p "$compiled"
xcrun actool DiThoi/Assets.xcassets \
  --compile "$compiled" \
  --app-icon AppIcon \
  --platform iphonesimulator \
  --minimum-deployment-target 17.0 \
  --target-device iphone \
  --output-partial-info-plist "$compiled/partial.plist" \
  --output-format human-readable-text --errors --warnings --notices \
  | tee "$out/actool.log"

if grep -q "unassigned children" "$out/actool.log"; then
  echo
  echo "actool dropped children from AppIcon. Every slot in IconSlot.iPhone has"
  echo "to survive compilation — a dropped one is an icon iOS quietly falls back"
  echo "to a scaled neighbour for, which is the whole thing the optical cuts are"
  echo "for. See the comment on IconSlot.iPhone in Shared/TripMark.swift."
  exit 1
fi

xcrun assetutil --info "$compiled/Assets.car" | python3 -c '
import json, sys
renditions = [e for e in json.load(sys.stdin)
              if e.get("Name") == "AppIcon" and "RenditionName" in e]
names = {e["RenditionName"] for e in renditions}
appearances = {e.get("Appearance") for e in renditions if e.get("Appearance")}
for e in sorted(renditions, key=lambda e: (e.get("Appearance") or "", e.get("PixelWidth", 0))):
    print("  %-9s %5s  %s" % (e.get("Appearance") or "default",
                              e.get("PixelWidth"), e["RenditionName"]))
missing = []
if len(names) < 9:
    missing.append("only %d of the 9 default cuts survived" % len(names))
for wanted in ("UIAppearanceDark", "ISAppearanceTintable"):
    if wanted not in appearances:
        missing.append("no %s rendition" % wanted)
if missing:
    print("\n" + "\n".join(missing))
    sys.exit(1)
print("\n— 9 cuts, dark and tinted —")
'
