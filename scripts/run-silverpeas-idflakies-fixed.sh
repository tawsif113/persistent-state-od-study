#!/usr/bin/env bash

set -u
set -o pipefail

STUDY="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study"
PROJECT="$HOME/Desktop/projects/phd/shanto-UT-DALLAS/silverpeas-setup-idflakies"

BASE_SHA="6e3b5a66375f8b6ae177edfe06115376c3bfa681"

PATCH="$STUDY/patches/silverpeas-idflakies.patch"
ORDER="$STUDY/orders/silverpeas-idflakies-original-order.txt"

OUT="$STUDY/raw/silverpeas-idflakies-01"

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

echo "=== RECONSTRUCT DETECTOR CHECKOUT ==="

git -C "$PROJECT" reset --hard "$BASE_SHA"
git -C "$PROJECT" clean -fdx

git -C "$PROJECT" apply --check "$PATCH" || fail "Patch check failed"
git -C "$PROJECT" apply "$PATCH" || fail "Patch apply failed"

DEPLOY_DIR="$PROJECT/build/resources/test/deployments"

mkdir -p "$OUT/preflight"

{
    echo "study_revision=$(git -C "$STUDY" rev-parse HEAD)"
    echo "project_revision=$(git -C "$PROJECT" rev-parse HEAD)"
    echo "patch_sha256=$(sha256sum "$PATCH" | awk '{print $1}')"
    echo "order_sha256=$(sha256sum "$ORDER" | awk '{print $1}')"
    echo "deployment_dir=$DEPLOY_DIR"
    echo "java=$("$JAVA_HOME/bin/java" -version 2>&1 | head -1)"
} > "$OUT/metadata.txt"

cp "$ORDER" "$OUT/original-order.txt"

echo
echo "=== PREFLIGHT ==="

(
    cd "$PROJECT"
    ./gradlew --no-daemon testClasses
) 2>&1 | tee "$OUT/preflight/testClasses.log"

rc=${PIPESTATUS[0]}
echo "$rc" > "$OUT/preflight/exit-code.txt"

[[ "$rc" -eq 0 ]] || fail "testClasses preflight failed"

run_protocol() {
    protocol="$1"
    protocol_out="$OUT/$protocol"

    echo
    echo "============================================================"
    echo "PROTOCOL: $protocol"
    echo "============================================================"

    mkdir -p "$protocol_out/trace"

    # Identical initial persistent state.
    rm -rf "$DEPLOY_DIR"

    # Identical detector starting state.
    rm -rf "$PROJECT/.dtfixingtools"
    mkdir -p "$PROJECT/.dtfixingtools"

    cp "$ORDER" "$PROJECT/.dtfixingtools/original-order"

    {
        echo "protocol=$protocol"
        echo "deployments_exists_initial=$(test -e "$DEPLOY_DIR" && echo true || echo false)"
        echo "order_sha256=$(sha256sum "$ORDER" | awk '{print $1}')"
        echo
        cat "$ORDER"
    } > "$protocol_out/run-metadata.txt"

    (
        cd "$PROJECT"

        STUDY_PROTOCOL="$protocol" \
        SILVERPEAS_DEPLOY_DIR="$DEPLOY_DIR" \
        STUDY_TRACE_DIR="$protocol_out/trace" \
        ./gradlew testplugin \
          --no-daemon \
          -Dtestplugin.className=edu.illinois.cs.dt.tools.detection.DetectorPlugin \
          -Ddetector.detector_type=reverse \
          -Ddt.detector.original_order.all_must_pass=false
    ) 2>&1 | tee "$protocol_out/console.log"

    rc=${PIPESTATUS[0]}
    echo "$rc" > "$protocol_out/exit-code.txt"

    if [[ -d "$PROJECT/.dtfixingtools" ]]; then
        cp -a "$PROJECT/.dtfixingtools" "$protocol_out/dtfixingtools"
    fi

    if [[ -e "$DEPLOY_DIR" ]]; then
        {
            echo "exists=true"
            find "$DEPLOY_DIR" -maxdepth 3 \
              -printf '%y|%p|%s bytes\n' 2>/dev/null | sort
        } > "$protocol_out/deployments-after.txt"
    else
        echo "exists=false" > "$protocol_out/deployments-after.txt"
    fi

    echo "[$protocol] detector_exit=$rc"
}

run_protocol clean
run_protocol reused

echo
echo "=== EXPERIMENT COMPLETE ==="
echo "$OUT"
