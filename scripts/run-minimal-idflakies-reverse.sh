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
    OUT="$STUDY/raw/idflakies-reverse/$PROTOCOL"

    echo
    echo "========================================"
    echo "REVERSE DETECTOR — $PROTOCOL"
    echo "========================================"

    rm -rf "$OUT"
    mkdir -p "$OUT"

    # Both protocols begin from identical external state.
    rm -f "$MARKER"

    # No previous detector artifacts.
    rm -rf "$PROJECT/.dtfixingtools"

    # Fresh trace files for this experiment.
    rm -rf "$STUDY/raw/idflakies-minimal-trace/$PROTOCOL"

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
}

mkdir -p "$STUDY/raw/idflakies-reverse"

run_protocol clean
run_protocol reused

echo
echo "========================================"
echo "REVERSE EXPERIMENT FINISHED"
echo "========================================"
