# Persistent-State Order-Dependency Study

## Research question

How does cross-execution persistent state affect the detection of
order-dependent tests and the ranking of their relevant tests?

## Protocols

### Clean-state protocol

Persistent external state is reset before each test-order execution.

### Reused-state protocol

Persistent external state is allowed to survive across test-order
executions.

Matched comparisons use the same test orders under both protocols.

## Controlled filesystem case

A = `testA_stateSetter_writesFile`

B = `testB_brittle_readsFile`

Expected dependency:

- A -> B: B passes.
- B -> A under clean state: B fails.
- B -> A under reused state: B may pass because the marker created by
  an earlier execution survives.

## Current controlled iDFlakies result

Using a fixed original order:

- Original order: A -> B
- Reverse order: B -> A

Clean-state protocol:

- B in reverse order: ERROR
- iDFlakies detects B as order dependent.

Reused-state protocol:

- B in reverse order: PASS
- iDFlakies does not detect B.

The original and reverse orders are identical between the two protocols.

## Repository layout

- `cases/` - controlled and real subject cases
- `scripts/` - experiment runners
- `orders/` - fixed test-order artifacts
- `manifests/` - environment and integrity metadata
- `raw/` - preserved raw experiment output
- `processed/` - derived summaries and tables
- `report/` - report material
