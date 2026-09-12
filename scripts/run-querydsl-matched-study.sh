#!/usr/bin/env bash

set -u
set -o pipefail

STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"
PROJECT="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/querydsl-persistent-state"
JAVA8="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/toolchains/temurin8"

PROJECT_SHA="2bf234caf78549813a1e0f44d9c30ecc5ef734e3"

MODULE="$PROJECT/querydsl-hibernate-search"
POM="$MODULE/pom.xml"

LUCENE="$MODULE/target/lucene"
DERBY="$MODULE/target/derbydb"

ORDER_FILE="$STUDY/orders/querydsl-case-03-orders.csv"
EXPECTED_ORDER_SHA="9896baedac733ae1cde565b6afb5693cacfc7ec7929f812dee9f8204ec40199f"

RAW="$STUDY/raw/querydsl-matched-01"

A="com.querydsl.hibernate.search.SearchQueryTest#exists"
B="com.querydsl.hibernate.search.SearchQueryTest#listResults"

export JAVA_HOME="$JAVA8"
export PATH="$JAVA_HOME/bin:$PATH"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

reset_state() {
    rm -rf "$LUCENE" "$DERBY"
}

snapshot() {
    local protocol="$1"
    local execution="$2"
    local phase="$3"

    local file="$RAW/$protocol-$execution-$phase-state.txt"

    {
        echo -n "lucene_exists="
        [[ -e "$LUCENE" ]] && echo true || echo false

        echo -n "derby_exists="
        [[ -e "$DERBY" ]] && echo true || echo false

        if [[ -d "$LUCENE" ]]; then
            echo "lucene_files:"
            find "$LUCENE" -type f -printf '%P %s bytes\n' | sort
        fi
    } > "$file"
}

run_test() {
    local protocol="$1"
    local execution="$2"
    local label="$3"
    local test="$4"

    snapshot "$protocol" "$execution" "before"

    (
        cd "$PROJECT"
        mvn \
          -f "$POM" \
          -Dtest="$test" \
          test
    ) > "$RAW/$protocol-$execution-$label.log" 2>&1

    echo $? > "$RAW/$protocol-$execution-$label-exit-code.txt"

    snapshot "$protocol" "$execution" "after"
}

[[ -d "$PROJECT/.git" ]] || fail "Querydsl checkout missing"
[[ -x "$JAVA_HOME/bin/java" ]] || fail "JDK 8 missing"
[[ -f "$ORDER_FILE" ]] || fail "Order file missing"
[[ ! -e "$RAW" ]] || fail "Raw directory already exists: $RAW"

[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$PROJECT_SHA" ]] \
    || fail "Wrong Querydsl revision"

[[ -z "$(git -C "$PROJECT" status --short)" ]] \
    || fail "Querydsl checkout is dirty"

ACTUAL_ORDER_SHA="$(sha256sum "$ORDER_FILE" | awk '{print $1}')"

[[ "$ACTUAL_ORDER_SHA" == "$EXPECTED_ORDER_SHA" ]] \
    || fail "Order file hash mismatch"

mkdir -p "$RAW"

{
    echo "project_revision=$PROJECT_SHA"
    echo "order_file=$ORDER_FILE"
    echo "order_sha256=$ACTUAL_ORDER_SHA"
    echo "A=$A"
    echo "B=$B"
    echo "execution_model=separate_Maven_invocation_per_test"
    echo
    java -version 2>&1
    mvn -version
} > "$RAW/metadata.txt"

# -------------------------
# CLEAN PROTOCOL
# Reset before every execution.
# -------------------------

reset_state
run_test "clean" "01" "A" "$A"

reset_state
run_test "clean" "02" "B" "$B"

# -------------------------
# REUSED PROTOCOL
# Reset once, then preserve state across executions.
# -------------------------

reset_state
run_test "reused" "01" "A" "$A"

run_test "reused" "02" "B" "$B"

# Leave project state clean.
reset_state

echo "Querydsl matched clean-vs-reused study complete."
echo "Raw evidence: $RAW"
