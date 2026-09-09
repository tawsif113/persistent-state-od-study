package com.example.flakylab;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class PersistentStateODTest {

    private static final Path MARKER_FILE =
            Paths.get(
                    "/home/kazi/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study",
                    "cases/controlled/idflakies-minimal/state/persistent-marker.txt"
            );

    private static final String PROTOCOL =
            System.getenv().getOrDefault("STUDY_PROTOCOL", "reused")
                    .toLowerCase();

    private static final long PID = ProcessHandle.current().pid();

    private static final Path TRACE_DIR =
            Paths.get(
                    "/home/kazi/Desktop/projects/phd/shanto-UT-DALLAS/persistent-state-od-study/raw",
                    "idflakies-minimal-trace",
                    PROTOCOL
            );

    private static final Path TRACE_FILE =
            TRACE_DIR.resolve("trace-" + PID + ".log");

    static {
        logTrace("ORDER_START_PRE_RESET");

        if ("clean".equals(PROTOCOL)) {
            try {
                Files.deleteIfExists(MARKER_FILE);
            } catch (IOException e) {
                throw new ExceptionInInitializerError(e);
            }
        } else if (!"reused".equals(PROTOCOL)) {
            throw new ExceptionInInitializerError(
                    "Unknown STUDY_PROTOCOL: " + PROTOCOL
            );
        }

        logTrace("ORDER_START_POST_RESET");
    }

    private static void logTrace(String event) {
        try {
            Files.createDirectories(TRACE_DIR);

            String line =
                    "timestamp=" + System.currentTimeMillis()
                    + ",pid=" + PID
                    + ",protocol=" + PROTOCOL
                    + ",event=" + event
                    + ",marker_exists=" + Files.exists(MARKER_FILE);

            Files.writeString(
                    TRACE_FILE,
                    line + System.lineSeparator(),
                    StandardOpenOption.CREATE,
                    StandardOpenOption.APPEND
            );

        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    @Test
    void testA_stateSetter_writesFile() throws IOException {
        logTrace("A_BEFORE");

        Files.writeString(
                MARKER_FILE,
                "written by persistent state-setter"
        );

        logTrace("A_AFTER");

        assertTrue(Files.exists(MARKER_FILE));
    }

    @Test
    void testB_brittle_readsFile() throws IOException {
        logTrace("B_BEFORE");

        assertTrue(
                Files.exists(MARKER_FILE),
                "Expected persistent marker file to exist"
        );

        assertEquals(
                "written by persistent state-setter",
                Files.readString(MARKER_FILE)
        );

        logTrace("B_AFTER");
    }

    @AfterAll
    static void orderFinished() {
        logTrace("ORDER_END");
    }
}
