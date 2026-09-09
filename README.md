# Persistent-State Order-Dependency Study

Research question:

> How does cross-execution persistent state affect the detection of
> order-dependent tests and the ranking of their relevant tests?

## Current scope

This repository contains controlled experiments comparing:

1. Clean-state protocol
   - persistent external state is reset before each test-order execution.

2. Reused-state protocol
   - persistent external state is allowed to survive across test-order
     executions.

The same test orders are used when making protocol comparisons.

## Controlled filesystem case

A = `testA_stateSetter_writesFile`

B = `testB_brittle_readsFile`

Known dependency:

- A -> B: B passes.
- B -> A with clean filesystem state: B fails.
- B -> A with filesystem state left by a previous execution: B can pass.

## Repository layout

- `cases/` - controlled and real subject cases
- `scripts/` - experiment runners and analysis scripts
- `orders/` - fixed test-order artifacts
- `manifests/` - environment and integrity metadata
- `raw/` - preserved raw experimental outputs
- `processed/` - derived tables and summaries
- `report/` - report material
