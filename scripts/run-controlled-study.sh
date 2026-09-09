#!/usr/bin/env bash

set -u

LAB="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/idflakies-lab"
STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"

MARKER="$LAB/notes/controlled-persistent-marker.txt"

TEST_CLASS="com.example.flakylab.ControlledPersistentStateTest"

JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

mkdir -p "$STUDY/raw/clean"
mkdir -p "$STUDY/raw/reused"

snapshot_state() {

    OUTPUT="$1"

    {
        echo "timestamp=$(date --iso-8601=seconds)"
        echo "path=$MARKER"

        if [ -f "$MARKER" ]; then
            echo "exists=true"
            echo "size=$(stat -c%s "$MARKER")"
            echo "mtime=$(stat -c%y "$MARKER")"
            echo "sha256=$(sha256sum "$MARKER" | awk '{print $1}')"
            echo "content=$(cat "$MARKER")"
        else
            echo "exists=false"
        fi

    } > "$OUTPUT"
}


run_order() {

    PROTOCOL="$1"
    NUMBER="$2"
    ORDER="$3"

    OUTDIR="$STUDY/raw/$PROTOCOL/order-${NUMBER}-${ORDER}"

    mkdir -p "$OUTDIR"

    echo "Running $PROTOCOL / order $NUMBER / $ORDER"

    snapshot_state "$OUTDIR/state-before.txt"

    cd "$LAB" || exit 1

    STUDY_ORDER="$ORDER" \
    ./gradlew test \
        --tests "$TEST_CLASS" \
        --rerun-tasks \
        --no-daemon \
        > "$OUTDIR/gradle.log" 2>&1

    EXIT_CODE=$?

    echo "$EXIT_CODE" > "$OUTDIR/exit-code.txt"

    snapshot_state "$OUTDIR/state-after.txt"

    if [ -d "$LAB/build/test-results/test" ]; then
        cp -r "$LAB/build/test-results/test" \
            "$OUTDIR/test-results"
    fi

    echo "exit_code=$EXIT_CODE"
    echo
}


echo "========================================"
echo "CLEAN-STATE PROTOCOL"
echo "========================================"

# Clean before EACH order.

rm -f "$MARKER"

run_order "clean" "01" "AB"

rm -f "$MARKER"

run_order "clean" "02" "BA"


echo "========================================"
echo "REUSED-STATE PROTOCOL"
echo "========================================"

# Reset only once before the sequence.

rm -f "$MARKER"

run_order "reused" "01" "AB"

# IMPORTANT:
# No reset here. State from AB is intentionally preserved.

run_order "reused" "02" "BA"


echo "========================================"
echo "DONE"
echo "========================================"
