#!/usr/bin/env python3

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "raw" / "querydsl-idflakies-01"
RESULT = ROOT / "results" / "querydsl-case-03-idflakies-result.txt"

A = "com.querydsl.hibernate.search.SearchQueryTest.exists"
B = "com.querydsl.hibernate.search.SearchQueryTest.listResults"

RAW_COMMIT = "5137964ce3dc4d2d543aabe796f2ad033fd0e788"


def load_json(path):
    with path.open() as f:
        return json.load(f)


def original_id(protocol):
    return (
        RAW
        / protocol
        / "dtfixingtools"
        / "detection-results"
        / "original-results-ids"
    ).read_text().strip()


def load_run(protocol, run_id):
    return load_json(
        RAW
        / protocol
        / "dtfixingtools"
        / "test-runs"
        / "results"
        / run_id
    )


def result_of(run, test):
    return run["results"][test]["result"]


def trace_groups(protocol):
    path = RAW / protocol / "trace.csv"
    groups = []
    by_pid = {}

    with path.open() as f:
        for row in csv.reader(f):
            proto, pid, timestamp, event, lucene, derby = row

            assert proto == protocol

            if pid not in by_pid:
                entry = {"pid": pid, "events": {}}
                by_pid[pid] = entry
                groups.append(entry)

            by_pid[pid]["events"][event] = {
                "lucene": lucene == "true",
                "derby": derby == "true",
                "timestamp": int(timestamp),
            }

    return groups


# ------------------------------------------------------------
# Fixed original order
# ------------------------------------------------------------

expected_order = [A, B]

for protocol in ("clean", "reused"):
    order = (
        RAW / protocol / "dtfixingtools" / "original-order"
    ).read_text().splitlines()

    assert order == expected_order


# ------------------------------------------------------------
# Clean protocol
# ------------------------------------------------------------

clean_reverse_meta = load_json(
    RAW
    / "clean"
    / "dtfixingtools"
    / "detection-results"
    / "reverse"
    / "round0.json"
)

clean_original = load_run("clean", original_id("clean"))
clean_reverse = load_run(
    "clean",
    clean_reverse_meta["testRunIds"][0]
)

assert clean_original["testOrder"] == [A, B]
assert result_of(clean_original, A) == "PASS"
assert result_of(clean_original, B) == "PASS"

assert clean_reverse["testOrder"] == [B, A]
assert result_of(clean_reverse, B) == "PASS"
assert result_of(clean_reverse, A) == "PASS"

assert clean_reverse_meta["unfilteredTests"]["dts"] == []
assert clean_reverse_meta["filteredTests"]["dts"] == []

assert (
    RAW
    / "clean"
    / "dtfixingtools"
    / "detection-results"
    / "list.txt"
).read_text().strip() == ""


# ------------------------------------------------------------
# Reused protocol
# ------------------------------------------------------------

reused_reverse_meta = load_json(
    RAW
    / "reused"
    / "dtfixingtools"
    / "detection-results"
    / "reverse"
    / "round0.json"
)

reused_original = load_run("reused", original_id("reused"))
reused_reverse = load_run(
    "reused",
    reused_reverse_meta["testRunIds"][0]
)

assert reused_original["testOrder"] == [A, B]
assert result_of(reused_original, A) == "PASS"
assert result_of(reused_original, B) == "PASS"

assert reused_reverse["testOrder"] == [B, A]
assert result_of(reused_reverse, B) == "ERROR"
assert result_of(reused_reverse, A) == "PASS"

candidates = reused_reverse_meta["unfilteredTests"]["dts"]
assert len(candidates) == 1

candidate = candidates[0]

assert candidate["name"] == B
assert candidate["intended"]["order"] == [A]
assert candidate["intended"]["result"] == "PASS"
assert candidate["revealed"]["order"] == []
assert candidate["revealed"]["result"] == "ERROR"

assert reused_reverse_meta["filteredTests"]["dts"] == []

verify_files = list(
    (
        RAW
        / "reused"
        / "dtfixingtools"
        / "detection-results"
        / "reverse-verify"
        / "round0.json"
    ).glob("*.json")
)

assert len(verify_files) == 1

verify = load_json(verify_files[0])

assert verify["testOrder"] == [A, B]
assert result_of(verify, A) == "PASS"
assert result_of(verify, B) == "ERROR"

assert (
    RAW
    / "reused"
    / "dtfixingtools"
    / "detection-results"
    / "list.txt"
).read_text().strip() == ""


# ------------------------------------------------------------
# Persistent-state trace checks
# ------------------------------------------------------------

clean_trace = trace_groups("clean")
reused_trace = trace_groups("reused")

# Clean has original + reverse JVMs.
assert len(clean_trace) == 2

clean_reverse_events = clean_trace[1]["events"]

assert clean_reverse_events["ORDER_START_PRE_RESET"]["lucene"] is True
assert clean_reverse_events["ORDER_START_POST_RESET"]["lucene"] is False

# Reused has original + reverse + verification JVMs.
assert len(reused_trace) == 3

reused_reverse_events = reused_trace[1]["events"]
reused_verify_events = reused_trace[2]["events"]

assert reused_reverse_events["ORDER_START_PRE_RESET"]["lucene"] is True
assert reused_reverse_events["ORDER_START_POST_RESET"]["lucene"] is True

assert reused_verify_events["ORDER_START_PRE_RESET"]["lucene"] is True
assert reused_verify_events["ORDER_START_POST_RESET"]["lucene"] is True


# ------------------------------------------------------------
# Deterministic result
# ------------------------------------------------------------

text = f"""Querydsl case #3 - iDFlakies persistent-state result

raw_evidence_commit={RAW_COMMIT}

A={A}
B={B}

detector=reverse
fixed_original_order=A -> B
reverse_order=B -> A

CLEAN PROTOCOL

original A -> B:
A=PASS
B=PASS

reverse B -> A:
B=PASS
A=PASS

reverse_order_lucene_pre_reset=true
reverse_order_lucene_post_reset=false

unfiltered_dt_candidates=0
final_reported_dts=0
final_idflakies_detected_od=false


REUSED PROTOCOL

original A -> B:
A=PASS
B=PASS

reverse B -> A:
B=ERROR
A=PASS

reverse_order_lucene_pre_reset=true
reverse_order_lucene_post_reset=true

unfiltered_dt_candidates=1
unfiltered_candidate={B}
candidate_intended_result=PASS
candidate_revealed_result=ERROR

verification_order=A -> B
verification_A=PASS
verification_B=ERROR

verification_lucene_pre_reset=true
verification_lucene_post_reset=true

filtered_dt_candidates=0
final_reported_dts=0
final_idflakies_detected_od=false


INTERPRETATION

Under clean-state execution, the original and reverse orders both pass, so
iDFlakies produces no order-dependent candidate.

Under reused-state execution, the Lucene index created during the original
order survives into the reverse-order JVM. listResults changes from its
intended PASS result to ERROR, so iDFlakies creates an unfiltered
order-dependent candidate.

The persistent Lucene state also survives into iDFlakies' verification JVM.
During verification, the original A -> B order no longer reproduces the
expected PASS result for listResults; B is ERROR. The candidate therefore
does not survive verification, and the final reported dependent-test list
is empty.

Thus persistent cross-execution state changes detector evidence and the
verification path even though the final reported dependent-test count is
zero under both protocols.

This case demonstrates a verification-contamination mechanism. It does not
establish how frequently this mechanism occurs across IDoFT.
"""

RESULT.parent.mkdir(exist_ok=True)
RESULT.write_text(text)

print("All Querydsl iDFlakies assertions passed.")
print(f"Wrote: {RESULT}")
