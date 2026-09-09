#!/usr/bin/env bash

set -u
set -o pipefail

STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"
PROJECT="$STUDY/cases/controlled/idflakies-minimal"
MARKER="$PROJECT/state/persistent-marker.txt"

ORDER_FILE="$STUDY/orders/minimal-original-order.txt"

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

run_protocol() {

    PROTOCOL="$1"
    OUT="$STUDY/raw/idflakies-reverse-fixed/$PROTOCOL"

    echo
    echo "========================================"
    echo "FIXED-ORDER REVERSE — $PROTOCOL"
    echo "========================================"

    rm -rf "$OUT"
    mkdir -p "$OUT"

    # Identical initial persistent state.
    rm -f "$MARKER"

    # Remove all previous detector state.
    rm -rf "$PROJECT/.dtfixingtools"

    # IMPORTANT:
    # Seed the exact SAME original order for both protocols.
    mkdir -p "$PROJECT/.dtfixingtools"
    cp "$ORDER_FILE" "$PROJECT/.dtfixingtools/original-order"

    # Clean traces belonging to this protocol.
    rm -rf "$STUDY/raw/idflakies-minimal-trace/$PROTOCOL"

    {
        echo "timestamp=$(date --iso-8601=seconds)"
        echo "protocol=$PROTOCOL"
        echo
        echo "PRESET ORIGINAL ORDER:"
        cat "$PROJECT/.dtfixingtools/original-order"
        echo
        echo "ORDER SHA256:"
        sha256sum "$PROJECT/.dtfixingtools/original-order"
        echo
        echo "marker_exists_initial=$(test -f "$MARKER" && echo true || echo false)"
    } > "$OUT/run-metadata.txt"

    cd "$PROJECT" || exit 1

    STUDY_PROTOCOL="$PROTOCOL" \
    ./gradlew testplugin \
      --no-daemon \
      -Dtestplugin.className=edu.illinois.cs.dt.tools.detection.DetectorPlugin \
      -Ddetector.detector_type=reverse \
      -Ddt.detector.original_order.all_must_pass=false \
      2>&1 | tee "$OUT/console.log"

    EXIT_CODE=${PIPESTATUS[0]}
    echo "$EXIT_CODE" > "$OUT/exit-code.txt"

    if [ -d "$PROJECT/.dtfixingtools" ]; then
        cp -a "$PROJECT/.dtfixingtools" "$OUT/dtfixingtools"
    fi

    if [ -f "$MARKER" ]; then
        {
            echo "exists=true"
            echo "sha256=$(sha256sum "$MARKER" | awk '{print $1}')"
            echo "content=$(cat "$MARKER")"
        } > "$OUT/marker-after.txt"
    else
        echo "exists=false" > "$OUT/marker-after.txt"
    fi

    echo "Exit code: $EXIT_CODE"
}

mkdir -p "$STUDY/raw/idflakies-reverse-fixed"

run_protocol clean
run_protocol reused

echo
echo "========================================"
echo "FIXED-ORDER EXPERIMENT FINISHED"
echo "========================================"
