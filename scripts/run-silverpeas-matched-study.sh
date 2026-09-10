#!/usr/bin/env bash
set -uo pipefail

STUDY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SILVERPEAS_REPO="${SILVERPEAS_REPO:-$(cd "$STUDY_ROOT/.." && pwd)/silverpeas-setup}"

EXPECTED_SHA="6e3b5a66375f8b6ae177edfe06115376c3bfa681"
TEST_CLASS="org.silverpeas.setup.installation.SilverpeasInstallationTaskTest"

ORDER_FILE="$STUDY_ROOT/orders/silverpeas-case-01-orders.csv"
OUT="$STUDY_ROOT/raw/silverpeas-matched-01"

JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -d "$SILVERPEAS_REPO/.git" ]] \
    || fail "Silverpeas repository not found: $SILVERPEAS_REPO"

ACTUAL_SHA="$(git -C "$SILVERPEAS_REPO" rev-parse HEAD)"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] \
    || fail "Silverpeas SHA mismatch: expected $EXPECTED_SHA, got $ACTUAL_SHA"

[[ -z "$(git -C "$SILVERPEAS_REPO" status --short)" ]] \
    || fail "Silverpeas working tree is not clean"

[[ -x "$JAVA_HOME/bin/java" ]] \
    || fail "Java executable not found under JAVA_HOME=$JAVA_HOME"

JAVA_VERSION="$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
echo "$JAVA_VERSION" | grep -q '"11\.' \
    || fail "This experiment requires Java 11: $JAVA_VERSION"

[[ -f "$ORDER_FILE" ]] || fail "Missing order file: $ORDER_FILE"
[[ ! -e "$OUT" ]] || fail "Output already exists: $OUT"

mkdir -p "$OUT"/{clean,reused,preflight}

DEPLOY_DIR="$SILVERPEAS_REPO/build/resources/test/deployments"

snapshot_state() {
    local output="$1"

    {
        echo "timestamp=$(date --iso-8601=seconds)"
        echo "deployment_dir=$DEPLOY_DIR"

        if [[ -e "$DEPLOY_DIR" ]]; then
            echo "exists=true"
            find "$DEPLOY_DIR" -maxdepth 3 \
                -printf '%y|%p|%s bytes\n' 2>/dev/null | sort
        else
            echo "exists=false"
        fi
    } > "$output"
}

run_test() {
    local protocol="$1"
    local order_id="$2"
    local position="$3"
    local label="$4"
    local method="$5"

    local base="$OUT/$protocol/order-${order_id}-pos-${position}-${label}"

    snapshot_state "${base}.state-before.txt"

    {
        echo "protocol=$protocol"
        echo "order_id=$order_id"
        echo "position=$position"
        echo "label=$label"
        echo "method=$method"
        echo "test=$TEST_CLASS.$method"
        echo "silverpeas_sha=$ACTUAL_SHA"
        echo "java_home=$JAVA_HOME"
        echo "command=./gradlew --no-daemon cleanTest test -x processTestResources --tests '$TEST_CLASS.$method' < /dev/null"
    } > "${base}.metadata.txt"

    (
        cd "$SILVERPEAS_REPO"
        ./gradlew --no-daemon \
            cleanTest test \
            -x processTestResources \
            --tests "$TEST_CLASS.$method" < /dev/null
    ) 2>&1 | tee "${base}.log"

    local rc=${PIPESTATUS[0]}
    echo "$rc" > "${base}.exit-code.txt"

    local xml="$SILVERPEAS_REPO/build/test-results/test/TEST-${TEST_CLASS}.xml"
    if [[ -f "$xml" ]]; then
        cp "$xml" "${base}.junit.xml"
    fi

    snapshot_state "${base}.state-after.txt"

    echo
    echo "[$protocol order=$order_id pos=$position $label] exit=$rc"
    echo
}

run_protocol() {
    local protocol="$1"

    echo
    echo "============================================================"
    echo "PROTOCOL: $protocol"
    echo "============================================================"

    # Both protocols begin from a known clean persistent-state baseline.
    rm -rf "$DEPLOY_DIR"
    snapshot_state "$OUT/$protocol/protocol-start-state.txt"

    for order_id in 01 02; do
        if [[ "$protocol" == "clean" ]]; then
            rm -rf "$DEPLOY_DIR"
        fi

        snapshot_state "$OUT/$protocol/order-${order_id}-start-state.txt"

        while IFS=, read -r position label method; do
            run_test "$protocol" "$order_id" "$position" "$label" "$method"
        done < <(
            awk -F, -v id="$order_id" \
                'NR > 1 && $1 == id {print $2 "," $3 "," $4}' \
                "$ORDER_FILE"
        )

        snapshot_state "$OUT/$protocol/order-${order_id}-end-state.txt"
    done

    local expected_executions
    local actual_executions

    expected_executions="$(
        awk -F, 'NR > 1 && NF >= 4 {count++} END {print count+0}' "$ORDER_FILE"
    )"

    actual_executions="$(
        find "$OUT/$protocol" -maxdepth 1 -type f \
            -name 'order-*-pos-*-*.exit-code.txt' \
            | awk 'END {print NR+0}'
    )"

    {
        echo "expected_executions=$expected_executions"
        echo "actual_executions=$actual_executions"
    } > "$OUT/$protocol/execution-count.txt"

    [[ "$actual_executions" -eq "$expected_executions" ]] \
        || fail "$protocol executed $actual_executions tests; expected $expected_executions"

    while IFS=, read -r expected_order expected_position expected_label expected_method; do
        [[ -n "$expected_order" ]] || continue

        expected_file="$OUT/$protocol/order-${expected_order}-pos-${expected_position}-${expected_label}.exit-code.txt"

        [[ -f "$expected_file" ]] \
            || fail "$protocol missing expected execution evidence: $expected_file"
    done < <(tail -n +2 "$ORDER_FILE")

    snapshot_state "$OUT/$protocol/protocol-end-state.txt"
}

echo "=== PREFLIGHT ==="

{
    echo "study_revision=$(git -C "$STUDY_ROOT" rev-parse HEAD)"
    echo "silverpeas_revision=$ACTUAL_SHA"
    echo "silverpeas_repo=$SILVERPEAS_REPO"
    echo "java_home=$JAVA_HOME"
    echo "java_version=$JAVA_VERSION"
    echo "deployment_dir=$DEPLOY_DIR"
} > "$OUT/metadata.txt"

cp "$ORDER_FILE" "$OUT/orders.csv"
sha256sum "$ORDER_FILE" > "$OUT/orders.sha256"

# Materialize compiled classes/resources before the measured protocols.
# The persistent deployment directory is reset after this step.
(
    cd "$SILVERPEAS_REPO"
    ./gradlew --no-daemon testClasses
) 2>&1 | tee "$OUT/preflight/testClasses.log"

PREFLIGHT_RC=${PIPESTATUS[0]}
echo "$PREFLIGHT_RC" > "$OUT/preflight/exit-code.txt"

[[ "$PREFLIGHT_RC" -eq 0 ]] || fail "Preflight testClasses failed"

rm -rf "$DEPLOY_DIR"
snapshot_state "$OUT/preflight/state-after-reset.txt"

run_protocol clean
run_protocol reused

echo "Experiment complete."
echo "Raw evidence: $OUT"
