#!/usr/bin/env python3

"""
Controlled RankF observed-outcome adapter.

RankF source basis:
  RankF_O/Preprocess/Ranking - ALL - MD/BSS/getCombinations.py
  SHA256:
  4ff985968ba1e2a0dd34f0ca47512a0c23bd80ae45916a864cf56ef7cc3f5935

The ranking-update logic below is a faithful extraction of the RankF BSS
implementation inspected for this study.

Intentional semantic change:
  Original RankF BSS getPassOrFail() derives PASS/FAIL from whether a known
  state-setter occurs before the brittle test.

  This adapter instead obtains PASS/FAIL from the experimentally observed
  JUnit result of the brittle test.

Everything else relevant to the controlled ranking calculation is retained:
  - zero initialization from the first order
  - methods-before-brittle candidate updates
  - heuristic 3, then heuristic 2 for ties, then heuristic 1 for ties
  - carry-forward of unchanged scores
  - removal of the brittle test
  - descending score sort
"""

import csv
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


RANKF_SOURCE_SHA256 = (
    "4ff985968ba1e2a0dd34f0ca47512a0c23bd80ae45916a864cf56ef7cc3f5935"
)

EXPECTED_EXPERIMENT_COMMIT = (
    "6b068e4c0d658eb81f37cbb39c736cd6826334f8"
)

BRITTLE = "B"
KNOWN_STATE_SETTER = "A"

EXPECTED_PROTOCOLS = ("clean", "reused")
EXPECTED_ORDER_IDS = ("01", "02", "03", "04")


def fail(message):
    raise SystemExit(f"ERROR: {message}")


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def parse_key_value_file(path):
    result = {}

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        result[key] = value

    return result


def load_orders(path):
    rows = []

    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        expected_header = ["order_id", "order_code", "rankf_order"]
        if reader.fieldnames != expected_header:
            fail(
                f"Unexpected order-file header: {reader.fieldnames}; "
                f"expected {expected_header}"
            )

        for row in reader:
            order_id = row["order_id"]
            order_code = row["order_code"]
            rankf_order = row["rankf_order"]

            parsed_rankf = rankf_order.split(":")

            if parsed_rankf != list(order_code):
                fail(
                    f"Order representation mismatch for {order_id}: "
                    f"{order_code} versus {rankf_order}"
                )

            if sorted(order_code) != ["A", "B", "C", "D"]:
                fail(
                    f"Order {order_id} is not exactly one permutation "
                    f"of A/B/C/D: {order_code}"
                )

            rows.append(
                {
                    "order_id": order_id,
                    "order_code": order_code,
                    "rankf_order": rankf_order,
                    "order": parsed_rankf,
                }
            )

    if tuple(row["order_id"] for row in rows) != EXPECTED_ORDER_IDS:
        fail(
            "Unexpected order IDs: "
            + str(tuple(row["order_id"] for row in rows))
        )

    return rows


def read_brittle_outcome(order_dir):
    result_dir = order_dir / "test-results"

    xml_files = sorted(result_dir.glob("TEST-*.xml"))

    if not xml_files:
        fail(f"No JUnit XML found in {result_dir}")

    matches = []

    for xml_file in xml_files:
        root = ET.parse(xml_file).getroot()

        for element in root.iter():
            if local_name(element.tag) != "testcase":
                continue

            name = element.attrib.get("name", "")

            if "testB_brittle" not in name:
                continue

            child_types = {
                local_name(child.tag)
                for child in element
            }

            if "skipped" in child_types:
                fail(
                    f"Brittle test was skipped in {xml_file}"
                )

            passed = not (
                "failure" in child_types
                or "error" in child_types
            )

            matches.append(
                {
                    "xml_file": xml_file,
                    "testcase_name": name,
                    "passed": passed,
                }
            )

    if len(matches) != 1:
        fail(
            f"Expected exactly one brittle-test result in {order_dir}; "
            f"found {len(matches)}"
        )

    return matches[0]


def parse_trace_file(path):
    events = []

    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        fields = {}

        for item in raw_line.split(","):
            if "=" not in item:
                fail(
                    f"Malformed trace field at {path}:{line_number}: {item}"
                )
            key, value = item.split("=", 1)
            fields[key] = value

        fields["_line_number"] = line_number
        events.append(fields)

    return events


def validate_trace(trace_dir, protocol, order_row):
    order_id = order_row["order_id"]
    expected_order = order_row["order_code"]

    trace_files = sorted(trace_dir.glob(f"trace-{order_id}-*.log"))

    if len(trace_files) != 1:
        fail(
            f"Expected exactly one trace for {protocol} order {order_id}; "
            f"found {len(trace_files)}"
        )

    events = parse_trace_file(trace_files[0])

    before_to_code = {
        "A_BEFORE": "A",
        "B_BEFORE": "B",
        "C_BEFORE": "C",
        "D_BEFORE": "D",
    }

    actual_order = "".join(
        before_to_code[event["event"]]
        for event in events
        if event.get("event") in before_to_code
    )

    if actual_order != expected_order:
        fail(
            f"Actual trace order mismatch for {protocol}/{order_id}: "
            f"expected {expected_order}, got {actual_order}"
        )

    post_reset = [
        event
        for event in events
        if event.get("event") == "ORDER_START_POST_RESET"
    ]

    b_before = [
        event
        for event in events
        if event.get("event") == "B_BEFORE"
    ]

    if len(post_reset) != 1:
        fail(
            f"Expected one ORDER_START_POST_RESET for "
            f"{protocol}/{order_id}"
        )

    if len(b_before) != 1:
        fail(
            f"Expected one B_BEFORE for {protocol}/{order_id}"
        )

    post_reset_marker = post_reset[0]["marker_exists"]
    b_marker = b_before[0]["marker_exists"]

    if protocol == "clean":
        if post_reset_marker != "false":
            fail(
                f"Clean protocol did not reset marker for order {order_id}"
            )

    if protocol == "reused":
        expected_post_reset = (
            "false" if order_id == "01" else "true"
        )

        if post_reset_marker != expected_post_reset:
            fail(
                f"Unexpected reused-state marker for order {order_id}: "
                f"expected {expected_post_reset}, "
                f"got {post_reset_marker}"
            )

    return {
        "trace_file": trace_files[0],
        "actual_order": actual_order,
        "post_reset_marker_exists": post_reset_marker,
        "b_marker_exists": b_marker,
    }


# ----------------------------------------------------------------------
# RankF BSS score-update logic
# ----------------------------------------------------------------------

def heuristic_one(is_pass, old_rank):
    if is_pass:
        return old_rank + 1
    return old_rank - 1


def heuristic_methods_before_brittle(
    old_rank,
    order,
    is_pass,
    brittle_index,
):
    no_of_methods = len(order[:brittle_index])

    if is_pass:
        return old_rank + (1 / no_of_methods)

    return old_rank - (1 / no_of_methods)


def heuristic_distance_to_brittle(
    old_rank,
    order,
    is_pass,
    brittle_index,
    method,
):
    no_of_methods_between = (
        len(order[:brittle_index]) - order.index(method)
    )

    if no_of_methods_between == 0:
        if is_pass:
            return old_rank + (1 / sys.maxsize)
        return old_rank - (1 / sys.maxsize)

    if is_pass:
        return old_rank + (1 / no_of_methods_between)

    return old_rank - (1 / no_of_methods_between)


def update_rank(
    old_rank,
    order,
    is_pass,
    brittle_index,
    method,
    mode,
):
    if mode == "1":
        return heuristic_one(is_pass, old_rank)

    if mode == "2":
        return heuristic_distance_to_brittle(
            old_rank,
            order,
            is_pass,
            brittle_index,
            method,
        )

    if mode == "3":
        return heuristic_methods_before_brittle(
            old_rank,
            order,
            is_pass,
            brittle_index,
        )

    fail(f"Unknown RankF heuristic mode: {mode}")


def are_values_unique(values_dict):
    values = list(values_dict.values())

    if len(list(values_dict.keys())) == 1:
        return True

    return len(values) == len(set(values))


def sort_dict(values_dict):
    return {
        key: value
        for key, value in sorted(
            values_dict.items(),
            key=lambda item: item[1],
            reverse=True,
        )
    }


def update_ranks(order, is_pass, last_ranks):
    new_ranks = {}

    brittle_index = order.index(BRITTLE)
    sub_order = order[:brittle_index]

    for method in sub_order:
        new_ranks[method] = update_rank(
            last_ranks[method],
            order,
            is_pass,
            brittle_index,
            method,
            "3",
        )

    if not are_values_unique(new_ranks):
        for method in sub_order:
            new_ranks[method] = update_rank(
                new_ranks[method],
                order,
                is_pass,
                brittle_index,
                method,
                "2",
            )

        if not are_values_unique(new_ranks):
            for method in sub_order:
                new_ranks[method] = update_rank(
                    new_ranks[method],
                    order,
                    is_pass,
                    brittle_index,
                    method,
                    "1",
                )

    for method in last_ranks.keys():
        if method not in new_ranks.keys():
            new_ranks[method] = last_ranks[method]

    if BRITTLE in new_ranks:
        del new_ranks[BRITTLE]

    return sort_dict(new_ranks)


def rank_protocol(order_rows, observed):
    # RankF getRankedLists() initializes all methods occurring in the
    # first order to zero before processing order 0.
    scores = {
        method: 0
        for method in order_rows[0]["order"]
    }

    scores = sort_dict(scores)

    history = []

    for row in order_rows:
        order_id = row["order_id"]
        is_pass = observed[order_id]["passed"]

        scores = update_ranks(
            row["order"],
            is_pass,
            scores,
        )

        history.append(
            {
                "order_id": order_id,
                "order": row["rankf_order"],
                "passed": is_pass,
                "scores": dict(scores),
            }
        )

    return history


def main():
    repo = Path(__file__).resolve().parent.parent

    raw_root = repo / "raw" / "rankf-controlled-01"
    output_root = repo / "processed" / "rankf-controlled-01"

    order_file = raw_root / "orders-used.csv"
    provenance_file = (
        repo / "manifests" / "rankf-local-artifact-sha256.txt"
    )
    experiment_metadata_file = (
        raw_root / "experiment-metadata.txt"
    )

    if not raw_root.is_dir():
        fail(f"Missing raw evidence: {raw_root}")

    if output_root.exists():
        fail(
            f"Processed output already exists: {output_root}; "
            "refusing to overwrite analysis evidence"
        )

    if not provenance_file.is_file():
        fail(f"Missing RankF provenance manifest: {provenance_file}")

    provenance_text = provenance_file.read_text(encoding="utf-8")

    expected_provenance_line = (
        RANKF_SOURCE_SHA256
        + "  RankF_O/Preprocess/Ranking - ALL - MD/BSS/"
        + "getCombinations.py"
    )

    if expected_provenance_line not in provenance_text:
        fail(
            "RankF source hash in provenance manifest does not match "
            "the adapter's declared source basis"
        )

    experiment_metadata = parse_key_value_file(
        experiment_metadata_file
    )

    experiment_commit = experiment_metadata.get("study_commit")

    if experiment_commit != EXPECTED_EXPERIMENT_COMMIT:
        fail(
            f"Unexpected experiment revision: {experiment_commit}; "
            f"expected {EXPECTED_EXPERIMENT_COMMIT}"
        )

    order_rows = load_orders(order_file)

    observed_by_protocol = {}
    observation_rows = []

    for protocol in EXPECTED_PROTOCOLS:
        protocol_root = raw_root / protocol

        if not protocol_root.is_dir():
            fail(f"Missing protocol evidence: {protocol_root}")

        observed_by_protocol[protocol] = {}

        for row in order_rows:
            order_id = row["order_id"]
            order_dir = protocol_root / "orders" / order_id

            if not order_dir.is_dir():
                fail(
                    f"Missing order evidence: {protocol}/{order_id}"
                )

            metadata = parse_key_value_file(
                order_dir / "metadata.txt"
            )

            if metadata.get("protocol") != protocol:
                fail(
                    f"Protocol metadata mismatch for "
                    f"{protocol}/{order_id}"
                )

            if metadata.get("order_id") != order_id:
                fail(
                    f"Order ID metadata mismatch for "
                    f"{protocol}/{order_id}"
                )

            if metadata.get("order_code") != row["order_code"]:
                fail(
                    f"Order-code metadata mismatch for "
                    f"{protocol}/{order_id}"
                )

            if metadata.get("rankf_order") != row["rankf_order"]:
                fail(
                    f"RankF-order metadata mismatch for "
                    f"{protocol}/{order_id}"
                )

            outcome = read_brittle_outcome(order_dir)

            trace = validate_trace(
                protocol_root / "traces",
                protocol,
                row,
            )

            observed_by_protocol[protocol][order_id] = {
                "passed": outcome["passed"],
            }

            observation_rows.append(
                {
                    "protocol": protocol,
                    "order_id": order_id,
                    "order_code": row["order_code"],
                    "rankf_order": row["rankf_order"],
                    "actual_trace_order": trace["actual_order"],
                    "brittle_outcome": (
                        "PASS" if outcome["passed"] else "FAIL"
                    ),
                    "post_reset_marker_exists":
                        trace["post_reset_marker_exists"],
                    "marker_at_b_before":
                        trace["b_marker_exists"],
                    "junit_testcase":
                        outcome["testcase_name"],
                }
            )

    histories = {
        protocol: rank_protocol(
            order_rows,
            observed_by_protocol[protocol],
        )
        for protocol in EXPECTED_PROTOCOLS
    }

    output_root.mkdir(parents=True)

    with (
        output_root / "observed-outcomes.csv"
    ).open("w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "protocol",
            "order_id",
            "order_code",
            "rankf_order",
            "actual_trace_order",
            "brittle_outcome",
            "post_reset_marker_exists",
            "marker_at_b_before",
            "junit_testcase",
        ]

        writer = csv.DictWriter(
            f,
            fieldnames=fieldnames,
        )

        writer.writeheader()
        writer.writerows(observation_rows)

    with (
        output_root / "rank-history.csv"
    ).open("w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "protocol",
            "order_id",
            "rankf_order",
            "brittle_outcome",
            "candidate",
            "score",
            "position",
        ]

        writer = csv.DictWriter(
            f,
            fieldnames=fieldnames,
        )

        writer.writeheader()

        for protocol in EXPECTED_PROTOCOLS:
            for step in histories[protocol]:
                for position, (candidate, score) in enumerate(
                    step["scores"].items(),
                    start=1,
                ):
                    writer.writerow(
                        {
                            "protocol": protocol,
                            "order_id": step["order_id"],
                            "rankf_order": step["order"],
                            "brittle_outcome": (
                                "PASS"
                                if step["passed"]
                                else "FAIL"
                            ),
                            "candidate": candidate,
                            "score": f"{score:.17g}",
                            "position": position,
                        }
                    )

    final_rows = []

    for protocol in EXPECTED_PROTOCOLS:
        final_scores = histories[protocol][-1]["scores"]

        for position, (candidate, score) in enumerate(
            final_scores.items(),
            start=1,
        ):
            final_rows.append(
                {
                    "protocol": protocol,
                    "candidate": candidate,
                    "score": f"{score:.17g}",
                    "position": position,
                    "known_state_setter": (
                        "true"
                        if candidate == KNOWN_STATE_SETTER
                        else "false"
                    ),
                }
            )

    with (
        output_root / "final-ranks.csv"
    ).open("w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "protocol",
            "candidate",
            "score",
            "position",
            "known_state_setter",
        ]

        writer = csv.DictWriter(
            f,
            fieldnames=fieldnames,
        )

        writer.writeheader()
        writer.writerows(final_rows)

    analysis_commit = subprocess.check_output(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        text=True,
    ).strip()

    clean_final = histories["clean"][-1]["scores"]
    reused_final = histories["reused"][-1]["scores"]

    clean_a_position = (
        list(clean_final.keys()).index(KNOWN_STATE_SETTER) + 1
    )
    reused_a_position = (
        list(reused_final.keys()).index(KNOWN_STATE_SETTER) + 1
    )

    summary_lines = [
        "Controlled RankF observed-outcome analysis",
        "",
        f"Raw experiment revision: {experiment_commit}",
        f"Analysis revision: {analysis_commit}",
        f"RankF source SHA256: {RANKF_SOURCE_SHA256}",
        "",
        "Semantic adaptation:",
        "RankF score-update heuristics are retained, but brittle-test",
        "PASS/FAIL is read from observed JUnit results instead of being",
        "generated from known BSS ground truth.",
        "",
        "Observed brittle outcomes:",
    ]

    for protocol in EXPECTED_PROTOCOLS:
        outcomes = []

        for row in order_rows:
            order_id = row["order_id"]
            outcome = observed_by_protocol[protocol][order_id]["passed"]

            outcomes.append(
                f"{order_id}={('PASS' if outcome else 'FAIL')}"
            )

        summary_lines.append(
            f"  {protocol}: " + ", ".join(outcomes)
        )

    summary_lines.extend(
        [
            "",
            "Final candidate ranking:",
            "  clean:",
        ]
    )

    for position, (candidate, score) in enumerate(
        clean_final.items(),
        start=1,
    ):
        summary_lines.append(
            f"    {position}. {candidate}  score={score:.17g}"
        )

    summary_lines.append("  reused:")

    for position, (candidate, score) in enumerate(
        reused_final.items(),
        start=1,
    ):
        summary_lines.append(
            f"    {position}. {candidate}  score={score:.17g}"
        )

    summary_lines.extend(
        [
            "",
            "Known state-setter A:",
            f"  clean position: {clean_a_position}",
            f"  reused position: {reused_a_position}",
            "",
            "Interpretation must be based on the recorded observations",
            "and final ranks above; this file does not estimate prevalence",
            "in real projects.",
        ]
    )

    (
        output_root / "summary.txt"
    ).write_text(
        "\n".join(summary_lines) + "\n",
        encoding="utf-8",
    )

    print("\n".join(summary_lines))


if __name__ == "__main__":
    main()
