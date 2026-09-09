package com.example.flakylab;

import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@TestMethodOrder(MethodOrderer.MethodName.class)
public class FilePersistentPollutionTest {

    private static final Path MARKER_FILE =
            Paths.get(
                    "/home/kazi/Desktop/projects/phd/shanto-UT-DALLAS/idflakies-lab/notes",
                    "persistent-marker.txt"
            );

    @Test
    void testA_polluter_writesFile() throws IOException {
        Files.writeString(
                MARKER_FILE,
                "written by persistent polluter"
        );

        assertTrue(Files.exists(MARKER_FILE));
    }

    @Test
    void testB_victim_readsFile() throws IOException {
        assertTrue(
                Files.exists(MARKER_FILE),
                "Expected persistent marker file to exist"
        );

        assertEquals(
                "written by persistent polluter",
                Files.readString(MARKER_FILE)
        );
    }
}