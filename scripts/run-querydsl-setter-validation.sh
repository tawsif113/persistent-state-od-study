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

RAW="$STUDY/raw/querydsl-setter-validation-01"

A="com.querydsl.hibernate.search.SearchQueryTest#exists"
B="com.querydsl.hibernate.search.SearchQueryTest#listResults"

export JAVA_HOME="$JAVA8"
export PATH="$JAVA_HOME/bin:$PATH"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -d "$PROJECT/.git" ]] || fail "Querydsl checkout missing"
[[ -x "$JAVA_HOME/bin/java" ]] || fail "JDK 8 missing"
[[ ! -e "$RAW" ]] || fail "Raw directory already exists: $RAW"

[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$PROJECT_SHA" ]] \
    || fail "Wrong Querydsl revision"

[[ -z "$(git -C "$PROJECT" status --short)" ]] \
    || fail "Querydsl checkout is dirty"

mkdir -p "$RAW"

reset_state() {
    rm -rf "$LUCENE" "$DERBY"
}

snapshot() {
    local name="$1"

    {
        echo -n "lucene_exists="
        [[ -e "$LUCENE" ]] && echo true || echo false

        echo -n "derby_exists="
        [[ -e "$DERBY" ]] && echo true || echo false

        if [[ -d "$LUCENE" ]]; then
            echo "lucene_files:"
            find "$LUCENE" -type f -printf '%P %s bytes\n' | sort
        fi
    } > "$RAW/$name-state.txt"
}

run_test() {
    local name="$1"
    local test="$2"

    snapshot "$name-before"

    (
        cd "$PROJECT"
        mvn \
          -f "$POM" \
          -Dtest="$test" \
          test
    ) > "$RAW/$name.log" 2>&1

    echo $? > "$RAW/$name-exit-code.txt"

    snapshot "$name-after"
}

{
    echo "project_revision=$PROJECT_SHA"
    echo "A=$A"
    echo "B=$B"
    echo "persistent_state=$LUCENE"
    echo "execution_model=separate_Maven_invocation_per_test"
    echo
    java -version 2>&1
    mvn -version
} > "$RAW/metadata.txt"

# Validate A as a state setter.
reset_state
run_test "01-A-clean" "$A"

# Preserve A-created filesystem state into a separate JVM execution of B.
run_test "02-B-after-A-reused" "$B"

# Causal reset control.
reset_state
run_test "03-B-after-reset" "$B"

# Leave project state clean.
reset_state

echo "Querydsl setter validation complete."
echo "Raw evidence: $RAW"
