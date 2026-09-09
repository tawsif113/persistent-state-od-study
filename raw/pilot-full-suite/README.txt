Pilot iDFlakies experiment.

Observed:
- Clean-state run detected:
  com.example.flakylab.IDFlakiesPersistentStateTest#testB_brittle_readsFile()
- Reused-state run did not report that test.

Limitation:
The Gradle/iDFlakies 1.1.0 invocation did not restrict discovery to the
two tests specified through dt.original.order. Existing synthetic tests
were also executed.

The clean and reused original-order files were also different.

Therefore this run is retained as preliminary evidence only and is not
used as the final same-orders controlled comparison.
