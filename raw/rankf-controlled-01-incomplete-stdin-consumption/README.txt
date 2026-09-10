INCOMPLETE EXECUTION — DO NOT USE AS EXPERIMENTAL RESULT

Runner revision:
e698d02 Add runner for matched controlled RankF executions

Observed behavior:
- clean protocol executed only order 01 (ACDB)
- reused protocol executed only order 01 (ACDB)
- orders 02, 03, and 04 were never executed

Cause:
The Gradle invocation inherited stdin from the shell while-loop whose
stdin was orders/rankf-controlled-orders.csv. Gradle consumed the
remaining CSV input, causing the loop to terminate after its first row.

This artifact is preserved only as evidence of the failed runner
execution. It is not part of the clean-vs-reused experimental results.

The corrected runner must isolate Gradle stdin from the order-file
stream before the experiment is rerun.
