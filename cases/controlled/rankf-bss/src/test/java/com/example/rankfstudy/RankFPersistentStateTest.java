package com.example.rankfstudy;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.MethodDescriptor;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.MethodOrdererContext;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@TestMethodOrder(RankFPersistentStateTest.StudyOrderer.class)
public class RankFPersistentStateTest {

    private static final String PROTOCOL = requiredEnv("STUDY_PROTOCOL");
    private static final String ORDER = requiredEnv("STUDY_ORDER");
    private static final String ORDER_ID = requiredEnv("STUDY_ORDER_ID");

    private static final Path MARKER_FILE =
            Paths.get(requiredEnv("STUDY_MARKER_FILE"));

    private static final Path TRACE_DIR =
            Paths.get(requiredEnv("STUDY_TRACE_DIR"));

    private static final long PID = ProcessHandle.current().pid();

    private static final Path TRACE_FILE =
            TRACE_DIR.resolve(
                    "trace-" + ORDER_ID + "-" + PID + ".log"
            );

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

    private static String requiredEnv(String name) {
        String value = System.getenv(name);

        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    "Missing required environment variable: " + name
            );
        }

        return value;
    }

    private static void logTrace(String event) {
        try {
            Files.createDirectories(TRACE_DIR);

            String line =
                    "timestamp=" + System.currentTimeMillis()
                    + ",pid=" + PID
                    + ",protocol=" + PROTOCOL
                    + ",order_id=" + ORDER_ID
                    + ",order=" + ORDER
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
    void testA_stateSetter() throws IOException {
        logTrace("A_BEFORE");

        Files.createDirectories(MARKER_FILE.getParent());

        Files.writeString(
                MARKER_FILE,
                "written by rankf controlled state-setter"
        );

        logTrace("A_AFTER");

        assertTrue(Files.exists(MARKER_FILE));
    }

    @Test
    void testB_brittle() throws IOException {
        logTrace("B_BEFORE");

        assertTrue(
                Files.exists(MARKER_FILE),
                "Expected persistent marker file to exist"
        );

        assertEquals(
                "written by rankf controlled state-setter",
                Files.readString(MARKER_FILE)
        );

        logTrace("B_PASS");
    }

    @Test
    void testC_neutral() {
        logTrace("C_BEFORE");
        logTrace("C_AFTER");
    }

    @Test
    void testD_neutral() {
        logTrace("D_BEFORE");
        logTrace("D_AFTER");
    }

    @AfterAll
    static void orderFinished() {
        logTrace("ORDER_END");
    }

    public static class StudyOrderer implements MethodOrderer {

        @Override
        public void orderMethods(MethodOrdererContext context) {

            Map<Character, String> methods = new HashMap<>();
            methods.put('A', "testA_stateSetter");
            methods.put('B', "testB_brittle");
            methods.put('C', "testC_neutral");
            methods.put('D', "testD_neutral");

            if (ORDER.length() != 4) {
                throw new IllegalArgumentException(
                        "STUDY_ORDER must contain exactly four letters: "
                        + ORDER
                );
            }

            Map<String, Integer> rank = new HashMap<>();

            for (int i = 0; i < ORDER.length(); i++) {
                char code = ORDER.charAt(i);
                String method = methods.get(code);

                if (method == null) {
                    throw new IllegalArgumentException(
                            "Unknown test code in STUDY_ORDER: " + code
                    );
                }

                if (rank.put(method, i) != null) {
                    throw new IllegalArgumentException(
                            "Duplicate test code in STUDY_ORDER: " + code
                    );
                }
            }

            context.getMethodDescriptors().sort(
                    (left, right) -> Integer.compare(
                            rankFor(left, rank),
                            rankFor(right, rank)
                    )
            );
        }

        private int rankFor(
                MethodDescriptor descriptor,
                Map<String, Integer> rank
        ) {
            Integer value =
                    rank.get(descriptor.getMethod().getName());

            if (value == null) {
                throw new IllegalStateException(
                        "Unexpected test method: "
                        + descriptor.getMethod().getName()
                );
            }

            return value;
        }
    }
}
