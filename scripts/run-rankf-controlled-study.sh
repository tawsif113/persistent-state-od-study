#!/usr/bin/env bash

set -euo pipefail

STUDY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$STUDY/cases/controlled/rankf-bss"
ORDER_FILE="$STUDY/orders/rankf-controlled-orders.csv"

MARKER="$PROJECT/state/persistent-marker.txt"
OUT_ROOT="$STUDY/raw/rankf-controlled-01"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"

TEST_CLASS="com.example.rankfstudy.RankFPersistentStateTest"

if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
    echo "ERROR: JAVA_HOME does not contain an executable java: $JAVA_HOME" >&2
    exit 1
fi

if ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "11\.'; then
    echo "ERROR: This experiment requires JDK 11." >&2
    "$JAVA_HOME/bin/java" -version >&2
    exit 1
fi

if [[ ! -f "$ORDER_FILE" ]]; then
    echo "ERROR: Missing order file: $ORDER_FILE" >&2
    exit 1
fi

# Never silently overwrite preserved experimental evidence.
if [[ -e "$OUT_ROOT" ]]; then
    echo "ERROR: Output already exists: $OUT_ROOT" >&2
    echo "Refusing to overwrite experimental evidence." >&2
    exit 1
fi

mkdir -p "$OUT_ROOT"

record_marker() {
    local destination="$1"

    if [[ -f "$MARKER" ]]; then
        {
            echo "exists=true"
            echo "sha256=$(sha256sum "$MARKER" | awk '{print $1}')"
            printf "content="
            cat "$MARKER"
            echo
        } > "$destination"
    else
        echo "exists=false" > "$destination"
    fi
}

{
    echo "study_commit=$(git -C "$STUDY" rev-parse HEAD)"
    echo "timestamp=$(date --iso-8601=seconds)"
    echo "java_home=$JAVA_HOME"
    "$JAVA_HOME/bin/java" -version 2>&1
    echo
    echo "order_file=$ORDER_FILE"
    echo "order_file_sha256=$(sha256sum "$ORDER_FILE" | awk '{print $1}')"
    echo
    echo "test_source_sha256=$(sha256sum \
        "$PROJECT/src/test/java/com/example/rankfstudy/RankFPersistentStateTest.java" \
        | awk '{print $1}')"
} > "$OUT_ROOT/experiment-metadata.txt"

cp "$ORDER_FILE" "$OUT_ROOT/orders-used.csv"

run_protocol() {
    local protocol="$1"
    local protocol_out="$OUT_ROOT/$protocol"

    mkdir -p "$protocol_out/orders"
    mkdir -p "$protocol_out/traces"

    # Both protocols begin from the same persistent-state condition.
    rm -f "$MARKER"

    record_marker "$protocol_out/protocol-initial-marker.txt"

    while IFS=, read -r order_id order_code rankf_order; do
        [[ "$order_id" == "order_id" ]] && continue
        [[ -z "$order_id" ]] && continue

        # Mechanical consistency check between execution code and RankF notation.
        normalized_rankf_order="${rankf_order//:/}"

        if [[ "$normalized_rankf_order" != "$order_code" ]]; then
            echo "ERROR: Order mismatch for $order_id" >&2
            echo "order_code=$order_code" >&2
            echo "rankf_order=$rankf_order" >&2
            exit 1
        fi

        order_out="$protocol_out/orders/$order_id"
        mkdir -p "$order_out"

        {
            echo "protocol=$protocol"
            echo "order_id=$order_id"
            echo "order_code=$order_code"
            echo "rankf_order=$rankf_order"
            echo "timestamp_start=$(date --iso-8601=seconds)"
        } > "$order_out/metadata.txt"

        record_marker "$order_out/marker-before.txt"

        # Remove only Gradle test-result output from the previous execution.
        # Persistent study state is controlled exclusively by the protocol.
        rm -rf "$PROJECT/build/test-results/test"
        rm -rf "$PROJECT/build/reports/tests/test"

        set +e

        (
            cd "$PROJECT"

            STUDY_PROTOCOL="$protocol" \
            STUDY_ORDER="$order_code" \
            STUDY_ORDER_ID="$order_id" \
            STUDY_MARKER_FILE="$MARKER" \
            STUDY_TRACE_DIR="$protocol_out/traces" \
            ./gradlew test \
                --tests "$TEST_CLASS" \
                --no-daemon \
                --rerun-tasks
        ) > >(tee "$order_out/console.log") 2>&1

        exit_code=$?

        set -e

        echo "$exit_code" > "$order_out/exit-code.txt"

        if [[ -d "$PROJECT/build/test-results/test" ]]; then
            cp -a \
                "$PROJECT/build/test-results/test" \
                "$order_out/test-results"
        fi

        record_marker "$order_out/marker-after.txt"

        {
            echo "timestamp_end=$(date --iso-8601=seconds)"
            echo "gradle_exit_code=$exit_code"
        } >> "$order_out/metadata.txt"

        echo
        echo "[$protocol][$order_id] $order_code -> exit=$exit_code"
        echo

    done < "$ORDER_FILE"

    record_marker "$protocol_out/protocol-final-marker.txt"
}

run_protocol clean
run_protocol reused

echo
echo "=================================================="
echo "CONTROLLED RANKF EXECUTION COMPLETE"
echo "Raw evidence: $OUT_ROOT"
echo "=================================================="
