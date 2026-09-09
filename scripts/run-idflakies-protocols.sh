#!/usr/bin/env bash

set -u
set -o pipefail

LAB="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/idflakies-lab"
STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"

MARKER="$LAB/notes/idflakies-persistent-marker.txt"
ORDER_FILE="$STUDY/orders/idflakies-persistent-pair.txt"

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

run_protocol() {

    PROTOCOL="$1"
    OUT="$STUDY/raw/idflakies/$PROTOCOL"

    echo
    echo "========================================"
    echo "Running protocol: $PROTOCOL"
    echo "========================================"

    rm -rf "$OUT"
    mkdir -p "$OUT"

    # Every protocol starts from the same initial external state.
    rm -f "$MARKER"

    # Remove previous iDFlakies results so historical rounds cannot leak
    # from one protocol invocation into the other.
    rm -rf "$LAB/.dtfixingtools"

    # Remove any old failure-output files.
    rm -f "$LAB"/failing-test-output-*

    # Preserve starting marker state.
    if [ -f "$MARKER" ]; then
        echo "exists=true" > "$OUT/marker-before.txt"
    else
        echo "exists=false" > "$OUT/marker-before.txt"
    fi

    cd "$LAB" || exit 1

    STUDY_PROTOCOL="$PROTOCOL" \
    ./gradlew testplugin \
      --no-daemon \
      -Dtestplugin.className=edu.illinois.cs.dt.tools.detection.DetectorPlugin \
      -Ddetector.detector_type=random-class-method \
      -Ddt.randomize.rounds=10 \
      -Ddt.detector.original_order.all_must_pass=false \
      -Ddt.seed=42 \
      -Ddt.original.order="$ORDER_FILE" \
      2>&1 | tee "$OUT/console.log"

    EXIT_CODE=${PIPESTATUS[0]}
    echo "$EXIT_CODE" > "$OUT/exit-code.txt"

    # Preserve the complete detector output.
    if [ -d "$LAB/.dtfixingtools" ]; then
        cp -a "$LAB/.dtfixingtools" "$OUT/dtfixingtools"
    fi

    # Preserve any subprocess failure logs.
    shopt -s nullglob
    FAIL_FILES=("$LAB"/failing-test-output-*)
    if [ ${#FAIL_FILES[@]} -gt 0 ]; then
        mkdir -p "$OUT/failing-test-output"
        cp -a "${FAIL_FILES[@]}" "$OUT/failing-test-output/"
    fi
    shopt -u nullglob

    # Preserve ending marker state.
    if [ -f "$MARKER" ]; then
        {
            echo "exists=true"
            echo "size=$(stat -c%s "$MARKER")"
            echo "sha256=$(sha256sum "$MARKER" | awk '{print $1}')"
            echo "content=$(cat "$MARKER")"
        } > "$OUT/marker-after.txt"
    else
        echo "exists=false" > "$OUT/marker-after.txt"
    fi

    echo "Protocol $PROTOCOL exit code: $EXIT_CODE"
}


mkdir -p "$STUDY/raw/idflakies"

# Clear protocol traces from previous attempts.
rm -rf "$STUDY/raw/idflakies-protocol-trace/clean"
rm -rf "$STUDY/raw/idflakies-protocol-trace/reused"

run_protocol clean
run_protocol reused

echo
echo "========================================"
echo "Both protocols finished"
echo "========================================"
