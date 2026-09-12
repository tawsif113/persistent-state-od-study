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

RAW="$STUDY/raw/querydsl-manual-01"

TEST="com.querydsl.hibernate.search.SearchQueryTest#listResults"

export JAVA_HOME="$JAVA8"
export PATH="$JAVA_HOME/bin:$PATH"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ -d "$PROJECT/.git" ]] || fail "Querydsl checkout missing"
[[ -x "$JAVA_HOME/bin/java" ]] || fail "JDK 8 missing"
[[ ! -e "$RAW" ]] || fail "Raw output already exists: $RAW"

[[ "$(git -C "$PROJECT" rev-parse HEAD)" == "$PROJECT_SHA" ]] \
    || fail "Wrong Querydsl revision"

[[ -z "$(git -C "$PROJECT" status --short)" ]] \
    || fail "Querydsl checkout is dirty"

mkdir -p "$RAW"

{
    echo "project_revision=$PROJECT_SHA"
    echo "test=$TEST"
    echo "lucene_state=$LUCENE"
    echo "derby_state=$DERBY"
    echo "execution_model=one_Maven_invocation_per_test"
    echo
    java -version 2>&1
    mvn -version
} > "$RAW/metadata.txt"

state_snapshot() {
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

    state_snapshot "$name-before"

    (
        cd "$PROJECT"
        mvn \
          -f "$POM" \
          -Dtest="$TEST" \
          test
    ) > "$RAW/$name.log" 2>&1

    echo $? > "$RAW/$name-exit-code.txt"

    state_snapshot "$name-after"
}

# Known-clean initial condition.
rm -rf "$LUCENE" "$DERBY"

# 1. Baseline from clean persistent state.
run_test "01-clean"

# 2. Separate Maven/JVM invocation, intentionally preserve Lucene state.
run_test "02-reused"

# 3. Explicit reset to test whether the outcome returns to baseline.
rm -rf "$LUCENE" "$DERBY"
run_test "03-reset"

# Leave the checkout in a clean persistent-state condition.
rm -rf "$LUCENE" "$DERBY"

echo "Querydsl manual persistent-state run complete."
echo "Raw evidence: $RAW"
