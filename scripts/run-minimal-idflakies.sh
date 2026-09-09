#!/usr/bin/env bash

set -u
set -o pipefail

STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"
PROJECT="$STUDY/cases/controlled/idflakies-minimal"
MARKER="$PROJECT/state/persistent-marker.txt"

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

run_protocol() {
    PROTOCOL="$1"
    OUT="$STUDY/raw/idflakies-minimal/$PROTOCOL"

    echo
    echo "========================================"
    echo "PROTOCOL: $PROTOCOL"
    echo "========================================"

    rm -rf "$OUT"
    mkdir -p "$OUT"

    # Both protocols begin from identical external state.
    rm -f "$MARKER"

    # Prevent any previous detector artifacts from influencing this run.
    rm -rf "$PROJECT/.dtfixingtools"

    # Remove traces for this protocol.
    rm -rf "$STUDY/raw/idflakies-minimal-trace/$PROTOCOL"

    {
        echo "timestamp=$(date --iso-8601=seconds)"
        echo "protocol=$PROTOCOL"
        echo "marker_exists_before=$(test -f "$MARKER" && echo true || echo false)"
    } > "$OUT/run-metadata.txt"

    cd "$PROJECT" || exit 1

    STUDY_PROTOCOL="$PROTOCOL" \
    ./gradlew testplugin \
      --no-daemon \
      -Dtestplugin.className=edu.illinois.cs.dt.tools.detection.DetectorPlugin \
      -Ddetector.detector_type=random-class-method \
      -Ddt.randomize.rounds=10 \
      -Ddt.detector.original_order.all_must_pass=false \
      -Ddt.seed=42 \
      2>&1 | tee "$OUT/console.log"

    EXIT_CODE=${PIPESTATUS[0]}
    echo "$EXIT_CODE" > "$OUT/exit-code.txt"

    if [ -d "$PROJECT/.dtfixingtools" ]; then
        cp -a "$PROJECT/.dtfixingtools" "$OUT/dtfixingtools"
    fi

    {
        echo "marker_exists_after=$(test -f "$MARKER" && echo true || echo false)"

        if [ -f "$MARKER" ]; then
            echo "marker_sha256=$(sha256sum "$MARKER" | awk '{print $1}')"
            echo "marker_content=$(cat "$MARKER")"
        fi
    } >> "$OUT/run-metadata.txt"

    echo "Exit code: $EXIT_CODE"
}

mkdir -p "$STUDY/raw/idflakies-minimal"

run_protocol clean
run_protocol reused

echo
echo "========================================"
echo "FINISHED"
echo "========================================"
