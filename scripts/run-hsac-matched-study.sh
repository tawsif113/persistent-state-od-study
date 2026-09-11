#!/usr/bin/env bash

STUDY="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${HSAC_PROJECT:-$HOME/Desktop/projects/phd/shanto-UT-DALLAS/hsac-fitnesse-fixtures}"
RAW="$STUDY/raw/hsac-matched-01"
STATE="$PROJECT/src/test/resources/temp-copy.txt"
ORDERS="$STUDY/orders/hsac-case-02-orders.csv"

EXPECTED_PROJECT_REV="a64c18d9c4bac8271275c7b089d40be20f0604b5"
EXPECTED_ORDER_SHA="519ab2a69ad914feac3697edc1f2e1d50ee043d8e8b1d1ccae8130b252845465"

A="nl.hsac.fitnesse.fixture.slim.FileFixtureTest#testCopyTo"
B="nl.hsac.fitnesse.fixture.slim.FileFixtureTest#testDelete"

state() {
    if [ -e "$STATE" ]; then
        echo "PRESENT"
    else
        echo "ABSENT"
    fi
}

if [ ! -d "$PROJECT/.git" ]; then
    echo "ERROR: HSAC checkout not found: $PROJECT"
    exit 2
fi

PROJECT_REV="$(git -C "$PROJECT" rev-parse HEAD)"
if [ "$PROJECT_REV" != "$EXPECTED_PROJECT_REV" ]; then
    echo "ERROR: wrong HSAC revision"
    echo "expected=$EXPECTED_PROJECT_REV"
    echo "actual=$PROJECT_REV"
    exit 2
fi

ORDER_SHA="$(sha256sum "$ORDERS" | awk '{print $1}')"
if [ "$ORDER_SHA" != "$EXPECTED_ORDER_SHA" ]; then
    echo "ERROR: order file hash mismatch"
    echo "expected=$EXPECTED_ORDER_SHA"
    echo "actual=$ORDER_SHA"
    exit 2
fi

if [ -e "$RAW" ]; then
    echo "ERROR: raw directory already exists: $RAW"
    echo "Refusing to overwrite evidence."
    exit 2
fi

mkdir -p "$RAW"

{
    echo "study_revision=$(git -C "$STUDY" rev-parse HEAD)"
    echo "project_revision=$PROJECT_REV"
    echo "order_sha256=$ORDER_SHA"
    echo "persistent_resource=$STATE"
    echo "execution_sequence=A_then_B"
    echo "execution_model=one_Maven_invocation_per_test"
    echo
    java -version 2>&1
    echo
    mvn -version
} > "$RAW/metadata.txt"

cp "$ORDERS" "$RAW/orders.csv"

printf '%s\n' \
    "protocol,execution_id,label,test,state_before,exit_code,state_after" \
    > "$RAW/summary.csv"

run_test() {
    PROTOCOL="$1"
    EXEC_ID="$2"
    LABEL="$3"
    TEST="$4"
    RESET_BEFORE="$5"

    if [ "$RESET_BEFORE" = "yes" ]; then
        rm -f "$STATE"
    fi

    BEFORE="$(state)"
    LOG="$RAW/${PROTOCOL}-${EXEC_ID}-${LABEL}.log"

    (
        cd "$PROJECT"
        mvn -Dtest="$TEST" test
    ) > "$LOG" 2>&1

    STATUS=$?
    AFTER="$(state)"

    printf '%s,%s,%s,%s,%s,%s,%s\n' \
        "$PROTOCOL" "$EXEC_ID" "$LABEL" "$TEST" \
        "$BEFORE" "$STATUS" "$AFTER" \
        >> "$RAW/summary.csv"

    {
        echo "protocol=$PROTOCOL"
        echo "execution_id=$EXEC_ID"
        echo "label=$LABEL"
        echo "test=$TEST"
        echo "reset_before=$RESET_BEFORE"
        echo "state_before=$BEFORE"
        echo "exit_code=$STATUS"
        echo "state_after=$AFTER"
    } > "$RAW/${PROTOCOL}-${EXEC_ID}-${LABEL}-state.txt"
}

# CLEAN:
# Same A -> B sequence, but persistent filesystem state is reset before
# every execution.
rm -f "$STATE"
run_test clean 01 A "$A" yes
run_test clean 02 B "$B" yes

# REUSED:
# Start from the same clean initial state, then preserve filesystem state
# between the same A -> B executions.
rm -f "$STATE"
run_test reused 01 A "$A" no
run_test reused 02 B "$B" no

# Leave checkout in baseline filesystem state after data collection.
rm -f "$STATE"

find "$RAW" -type f ! -name SHA256SUMS.txt -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    > "$RAW/SHA256SUMS.txt"

echo "=== HSAC MATCHED STUDY ==="
cat "$RAW/summary.csv"

echo
echo "=== CHECKSUMS ==="
(
    cd "$STUDY"
    sha256sum -c "raw/hsac-matched-01/SHA256SUMS.txt"
)
