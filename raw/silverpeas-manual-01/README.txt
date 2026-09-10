Silverpeas manual persistent-state reproduction
================================================

Project:
https://github.com/Silverpeas/Silverpeas-Setup

Revision:
6e3b5a66375f8b6ae177edfe06115376c3bfa681

Environment:
Java 11
Gradle 7.0

Brittle test (B):
org.silverpeas.setup.installation.SilverpeasInstallationTaskTest.testInstall

State-setter (A):
org.silverpeas.setup.installation.SilverpeasInstallationTaskTest.testInstallJustSilverpeas

Persistent filesystem resource:
<silverpeas-repo>/build/resources/test/deployments

Observed sequence
-----------------

1. Clean B-alone execution

Before:
deployments/ absent

Result:
B FAIL
Gradle exit = 1
java.io.IOException at SilverpeasInstallationTaskTest.groovy:54

After:
deployments/ absent


2. A-alone execution in a separate Gradle invocation

Before:
deployments/ absent

Result:
A PASS
Gradle exit = 0

After:
deployments/ exists


3. B execution in another separate Gradle invocation without resetting state

Before:
deployments/ exists

Result:
B PASS
Gradle exit = 0

After:
deployments/ exists


Interpretation
--------------
This manually reproduces cross-execution filesystem-state dependence.

The brittle test fails when the deployment directory is absent, while the same
test passes in a later execution when the directory created by an earlier
state-setter execution is preserved.

This is a causal/manual reproduction only. It is not yet the formal matched
clean-state versus reused-state experiment and is not yet an iDFlakies
detection result.
