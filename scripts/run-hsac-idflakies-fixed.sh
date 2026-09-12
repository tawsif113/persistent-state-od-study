#!/usr/bin/env bash

set -u
set -o pipefail

STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"
PROJECT="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/hsac-fitnesse-fixtures-idflakies"

BASE_SHA="a64c18d9c4bac8271275c7b089d40be20f0604b5"
HARNESS_SHA="2d6c7d64095dbda8713a3d8ae314584dd52b3ade"

PATCH="$STUDY/patches/hsac-idflakies.patch"
ORDER="$STUDY/orders/hsac-idflakies-original-order.txt"

EXPECTED_PATCH_SHA="eb4ad225f20e66bcc98a0d7e4dcca8e89953996684e39fe83cc83dc197b5a67e"
EXPECTED_ORDER_SHA="6250d7c2186433c5ac749aaa4383f362a715e9f6106fb44bdc54e2db3c22afb7"

OUT="$STUDY/raw/hsac-idflakies-01"

STATE_FILE="$PROJECT/src/test/resources/temp-copy.txt"

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -d "$PROJECT/.git" ]] || fail "Detector checkout missing"
[[ -f "$PATCH" ]] || fail "Patch missing"
[[ -f "$ORDER" ]] || fail "Order file missing"
[[ ! -e "$OUT" ]] || fail "Raw output already exists: $OUT"

[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$HARNESS_SHA" ]] \
    || fail "Detector checkout is not at harness commit"

[[ -z "$(git -C "$PROJECT" status --short)" ]] \
    || fail "Detector checkout is dirty"

[[ "$(git -C "$PROJECT" rev-parse "$BASE_SHA")" == "$BASE_SHA" ]] \
    || fail "Pinned base revision unavailable"

PATCH_SHA="$(sha256sum "$PATCH" | awk '{print $1}')"
ORDER_SHA="$(sha256sum "$ORDER" | awk '{print $1}')"

[[ "$PATCH_SHA" == "$EXPECTED_PATCH_SHA" ]] \
    || fail "Patch SHA256 mismatch"

[[ "$ORDER_SHA" == "$EXPECTED_ORDER_SHA" ]] \
    || fail "Order SHA256 mismatch"

mkdir -p "$OUT/preflight"

{
    echo "study_revision=$(git -C "$STUDY" rev-parse HEAD)"
    echo "project_base_revision=$BASE_SHA"
    echo "project_harness_revision=$HARNESS_SHA"
    echo "patch_sha256=$PATCH_SHA"
    echo "order_sha256=$ORDER_SHA"
    echo "persistent_resource=$STATE_FILE"
    echo "java=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
    echo "maven=$(mvn -version 2>&1 | head -1)"
} > "$OUT/metadata.txt"

cp "$ORDER" "$OUT/original-order.txt"

echo "=== PREFLIGHT ==="

(
    cd "$PROJECT"
    mvn -DskipTests test-compile
) 2>&1 | tee "$OUT/preflight/test-compile.log"

rc=${PIPESTATUS[0]}
echo "$rc" > "$OUT/preflight/exit-code.txt"

[[ "$rc" -eq 0 ]] || fail "test-compile preflight failed"

run_protocol() {
    protocol="$1"
    protocol_out="$OUT/$protocol"

    echo
    echo "============================================================"
    echo "PROTOCOL: $protocol"
    echo "============================================================"

    mkdir -p "$protocol_out"

    # Identical persistent-state starting point.
    rm -f "$STATE_FILE"

    # Identical detector starting point.
    rm -rf "$PROJECT/.dtfixingtools"
    mkdir -p "$PROJECT/.dtfixingtools"
    cp "$ORDER" "$PROJECT/.dtfixingtools/original-order"

    TRACE="$protocol_out/trace.csv"

    {
        echo "protocol=$protocol"
        echo "state_exists_initial=$(test -e "$STATE_FILE" && echo true || echo false)"
        echo "order_sha256=$(sha256sum "$PROJECT/.dtfixingtools/original-order" | awk '{print $1}')"
        echo "trace=$TRACE"
        echo
        cat "$PROJECT/.dtfixingtools/original-order"
    } > "$protocol_out/run-metadata.txt"

    (
        cd "$PROJECT"

        STUDY_PROTOCOL="$protocol" \
        STUDY_TRACE="$TRACE" \
        mvn testrunner:testplugin \
          -Ddetector.detector_type=reverse \
          -Ddt.detector.original_order.all_must_pass=false
    ) 2>&1 | tee "$protocol_out/console.log"

    rc=${PIPESTATUS[0]}
    echo "$rc" > "$protocol_out/exit-code.txt"

    if [[ -d "$PROJECT/.dtfixingtools" ]]; then
        cp -a "$PROJECT/.dtfixingtools" "$protocol_out/dtfixingtools"
    fi

    {
        echo "exists=$(test -e "$STATE_FILE" && echo true || echo false)"
        if [[ -e "$STATE_FILE" ]]; then
            stat "$STATE_FILE"
        fi
    } > "$protocol_out/state-after.txt"

    echo "[$protocol] detector_exit=$rc"
}

run_protocol clean
run_protocol reused

rm -f "$STATE_FILE"

echo
echo "=== EXPERIMENT COMPLETE ==="
echo "$OUT"
