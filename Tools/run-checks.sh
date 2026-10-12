#!/bin/bash
# Runs the model-layer checks on macOS — no simulator required.
#   ./Tools/run-checks.sh
#
# Every file in DiThoi/Model/ and Shared/ is compiled, minus the exclusions
# below. That direction matters: the list used to be written out by hand, so a
# new model file was picked up automatically by the Xcode project and silently
# *not* checked. Nothing failed; coverage just quietly dropped. Now the default
# is to be checked, and every exception has to be argued for here in the open.
#
# Shared/ is here for a second reason as well. Its files are ordinary
# `PBXFileReference`s in a hand-written project — unlike DiThoi/, which is a
# synchronised folder — so a new file there is *not* picked up by Xcode
# automatically. Globbing it means a new shared file is at least compiled and
# checked on the way to somebody noticing it needs a build-phase line too.
set -euo pipefail
cd "$(dirname "$0")/.."

# The files that can't build for macOS.
#
# `DocumentStore` turns passport scans into JPEGs, which means UIImage, so it
# can't be Foundation-only. It is also the reason "the model layer imports no
# UIKit" is a convention with an exception rather than a property of the
# directory — see CLAUDE.md.
#
# What it no longer contains is the crypto. AES-GCM and the Keychain's
# `OSStatus` branching live in `DocumentCrypto.swift`, which is Foundation-only
# and therefore checked: this exclusion used to mean that the one subsystem in
# the app whose silent failure is *unrecoverable* — a lost key makes every scan
# on the phone noise, permanently — had no coverage at all. Keep the split. If
# something crypto-shaped needs to be added, it goes over there.
#
# `Shared/Theme.swift`, `Shared/TripMarkView.swift` and `Shared/DayWidgetView.swift`
# are the design layer: SwiftUI, UIKit and WidgetKit, shared with the widget
# rather than with the checks.
# What they draw is checked through `Shared/TripMark.swift`, which is the
# arithmetic and is deliberately Foundation-only.
EXCLUDED=(
  "DiThoi/Model/DocumentStore.swift"
  "Shared/Theme.swift"
  "Shared/TripMarkView.swift"
  "Shared/DayWidgetView.swift"
)

sources=()
for file in DiThoi/Model/*.swift Shared/*.swift; do
  skip=""
  for excluded in "${EXCLUDED[@]}"; do
    [[ "$file" == "$excluded" ]] && skip=1
  done
  [[ -n "$skip" ]] || sources+=("$file")
done

echo "— compiling ${#sources[@]} model files —"
out=$(mktemp -d)

# The compiler is the authority on whether the model layer is still
# Foundation-only — grepping for `import UIKit` can't tell an unconditional
# import from one inside `#if canImport(UIKit)`, which is how PhotoStore
# legitimately splits file handling from image handling. So build, and if the
# build fails, say what the likely cause is rather than leaving the next person
# to work out why a new file broke a script they didn't touch.
if ! xcrun swiftc -O -parse-as-library \
  "${sources[@]}" \
  Tools/CheckTrip.swift \
  Tools/VerifyTrip.swift \
  -o "$out/verify"; then
  echo
  echo "The model checks build for macOS. If the errors above are about UIKit or"
  echo "SwiftUI, a file in DiThoi/Model/ has taken a platform dependency: either"
  echo "put the platform half behind #if canImport(UIKit) — the way PhotoStore"
  echo "does — or add the file to EXCLUDED at the top of this script and say why."
  exit 1
fi

"$out/verify"
