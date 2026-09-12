#!/usr/bin/env bash

set -u
set -o pipefail

STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"
PROJECT="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/querydsl-idflakies"
JAVA8="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/toolchains/temurin8"

BASE_SHA="2bf234caf78549813a1e0f44d9c30ecc5ef734e3"
HARNESS_SHA="4f6c1074d75d93936f1607ac2ff1f64aa3ce8e0d"

MODULE="$PROJECT/querydsl-hibernate-search"
POM="$MODULE/pom.xml"

PATCH="$STUDY/patches/querydsl-idflakies.patch"
ORDER="$STUDY/orders/querydsl-idflakies-original-order.txt"

EXPECTED_PATCH_SHA="b326a7bd616838ff6d4f3dd704fce102932175f0bf219b1b99767083b75c42ad"
EXPECTED_ORDER_SHA="103675e39b61b3fe7e4ec0a0f46107ccf4fc7f8494dd67b7aaf157258d1ed1dc"

EXPECTED_IDFLAKIES_SHA="9c2056143ea8961ba39d3ca147fa076e0a8dcb388e449cfec0cc0f6918ce192b"
EXPECTED_TESTRUNNER_SHA="55e4be10bb2b528e39adee34ee806971ff934469a4977bcf39fecd3ad414b321"

IDFLAKIES_JAR="$HOME/.m2/repository/edu/illinois/cs/idflakies/1.1.0/idflakies-1.1.0.jar"
TESTRUNNER_JAR="$HOME/.m2/repository/edu/illinois/cs/testrunner-maven-plugin/1.2/testrunner-maven-plugin-1.2.jar"

OUT="$STUDY/raw/querydsl-idflakies-01"

LUCENE="$MODULE/target/lucene"
DERBY="$MODULE/target/derbydb"
DT_DIR="$MODULE/.dtfixingtools"

export JAVA_HOME="$JAVA8"
export PATH="$JAVA_HOME/bin:$PATH"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -d "$PROJECT/.git" ]] || fail "Detector checkout missing"
[[ -x "$JAVA_HOME/bin/java" ]] || fail "JDK 8 missing"
[[ -f "$PATCH" ]] || fail "Patch missing"
[[ -f "$ORDER" ]] || fail "Order file missing"
[[ -f "$IDFLAKIES_JAR" ]] || fail "iDFlakies jar missing"
[[ -f "$TESTRUNNER_JAR" ]] || fail "testrunner jar missing"
[[ ! -e "$OUT" ]] || fail "Raw output already exists: $OUT"

[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$HARNESS_SHA" ]] \
    || fail "Detector checkout is not at harness revision"

[[ -z "$(git -C "$PROJECT" status --short)" ]] \
    || fail "Detector checkout is dirty"

[[ "$(git -C "$PROJECT" rev-parse "$BASE_SHA")" == "$BASE_SHA" ]] \
    || fail "Pinned Querydsl base revision unavailable"

PATCH_SHA="$(sha256sum "$PATCH" | awk '{print $1}')"
ORDER_SHA="$(sha256sum "$ORDER" | awk '{print $1}')"
IDFLAKIES_SHA="$(sha256sum "$IDFLAKIES_JAR" | awk '{print $1}')"
TESTRUNNER_SHA="$(sha256sum "$TESTRUNNER_JAR" | awk '{print $1}')"

[[ "$PATCH_SHA" == "$EXPECTED_PATCH_SHA" ]] \
    || fail "Patch SHA256 mismatch"

[[ "$ORDER_SHA" == "$EXPECTED_ORDER_SHA" ]] \
    || fail "Order SHA256 mismatch"

[[ "$IDFLAKIES_SHA" == "$EXPECTED_IDFLAKIES_SHA" ]] \
    || fail "iDFlakies artifact SHA256 mismatch"

[[ "$TESTRUNNER_SHA" == "$EXPECTED_TESTRUNNER_SHA" ]] \
    || fail "testrunner artifact SHA256 mismatch"

mkdir -p "$OUT/preflight"

{
    echo "study_revision=$(git -C "$STUDY" rev-parse HEAD)"
    echo "project_base_revision=$BASE_SHA"
    echo "project_harness_revision=$HARNESS_SHA"
    echo "patch_sha256=$PATCH_SHA"
    echo "order_sha256=$ORDER_SHA"
    echo "idflakies_sha256=$IDFLAKIES_SHA"
    echo "testrunner_sha256=$TESTRUNNER_SHA"
    echo "persistent_state=$LUCENE"
    echo "dtfixingtools=$DT_DIR"
    echo "java=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
    echo "maven=$(mvn -version 2>&1 | head -1)"
} > "$OUT/metadata.txt"

cp "$ORDER" "$OUT/original-order.txt"

echo "=== PREFLIGHT ==="

(
    cd "$MODULE"
    mvn -DskipTests -DskipITs test-compile
) 2>&1 | tee "$OUT/preflight/test-compile.log"

rc=${PIPESTATUS[0]}
echo "$rc" > "$OUT/preflight/exit-code.txt"

[[ "$rc" -eq 0 ]] || fail "test-compile preflight failed"

run_protocol() {
    local protocol="$1"
    local protocol_out="$OUT/$protocol"

    echo
    echo "============================================================"
    echo "PROTOCOL: $protocol"
    echo "============================================================"

    mkdir -p "$protocol_out"

    # Identical filesystem starting point for both protocols.
    rm -rf "$LUCENE" "$DERBY"

    # Identical detector starting point and identical original order.
    rm -rf "$DT_DIR"
    mkdir -p "$DT_DIR"
    cp "$ORDER" "$DT_DIR/original-order"

    local trace="$protocol_out/trace.csv"

    {
        echo "protocol=$protocol"
        echo "lucene_exists_initial=$(test -e "$LUCENE" && echo true || echo false)"
        echo "derby_exists_initial=$(test -e "$DERBY" && echo true || echo false)"
        echo "order_sha256=$(sha256sum "$DT_DIR/original-order" | awk '{print $1}')"
        echo "trace=$trace"
        echo
        cat "$DT_DIR/original-order"
    } > "$protocol_out/run-metadata.txt"

    (
        cd "$MODULE"

        STUDY_PROTOCOL="$protocol" \
        STUDY_TRACE="$trace" \
        mvn testrunner:testplugin \
          -Ddetector.detector_type=reverse \
          -Ddt.detector.original_order.all_must_pass=false
    ) 2>&1 | tee "$protocol_out/console.log"

    rc=${PIPESTATUS[0]}
    echo "$rc" > "$protocol_out/exit-code.txt"

    if [[ -d "$DT_DIR" ]]; then
        cp -a "$DT_DIR" "$protocol_out/dtfixingtools"
    fi

    {
        echo "lucene_exists=$(test -e "$LUCENE" && echo true || echo false)"
        echo "derby_exists=$(test -e "$DERBY" && echo true || echo false)"

        if [[ -d "$LUCENE" ]]; then
            echo "lucene_files:"
            find "$LUCENE" -type f -printf '%P %s bytes\n' | sort
        fi
    } > "$protocol_out/state-after.txt"

    echo "[$protocol] detector_exit=$rc"
}

run_protocol clean
run_protocol reused

rm -rf "$LUCENE" "$DERBY"

echo
echo "=== EXPERIMENT COMPLETE ==="
echo "$OUT"
