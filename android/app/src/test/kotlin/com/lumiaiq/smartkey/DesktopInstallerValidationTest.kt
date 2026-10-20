package com.lumiaiq.smartkey

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DesktopInstallerValidationTest {
    private val digest = "a".repeat(64)
    private val releasePath = "assets/desktop_installers/releases/1.2.3-0123456789ab"

    @Test
    fun acceptsOnlyVersionedInstallerAssetPathsAndBasenames() {
        assertNull(
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v1.2.3-Setup.exe",
                "LumiaKey-Windows-v1.2.3-Setup.exe",
                42,
                digest,
            ),
        )
        assertNull(
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-macOS-v1.2.3.dmg",
                "LumiaKey-macOS-v1.2.3.dmg",
                42,
                digest,
            ),
        )
        assertEquals(
            "Installer asset path is not allowlisted.",
            DesktopInstallerValidation.validateExport(
                "assets/other/LumiaKey-Windows-v1.2.3-Setup.exe",
                "LumiaKey-Windows-v1.2.3-Setup.exe",
                42,
                digest,
            ),
        )
        assertEquals(
            "Installer filename is invalid.",
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v1.2.3-Setup.exe",
                "../installer.exe",
                42,
                digest,
            ),
        )
        assertEquals(
            "Installer path and filename do not match.",
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v1.2.3-Setup.exe",
                "LumiaKey-macOS-v1.2.3.dmg",
                42,
                digest,
            ),
        )
    }

    @Test
    fun rejectsMismatchedReleaseAndInvalidIntegrityMetadata() {
        assertEquals(
            "Installer platform filename is not allowlisted for this release.",
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v9.9.9-Setup.exe",
                "LumiaKey-Windows-v9.9.9-Setup.exe",
                42,
                digest,
            ),
        )
        assertEquals(
            "Invalid installer size or SHA-256.",
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v1.2.3-Setup.exe",
                "LumiaKey-Windows-v1.2.3-Setup.exe",
                0,
                digest,
            ),
        )
        assertEquals(
            "Invalid installer size or SHA-256.",
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v1.2.3-Setup.exe",
                "LumiaKey-Windows-v1.2.3-Setup.exe",
                DesktopInstallerValidation.maxBytes + 1,
                digest,
            ),
        )
        assertEquals(
            "Invalid installer size or SHA-256.",
            DesktopInstallerValidation.validateExport(
                "$releasePath/LumiaKey-Windows-v1.2.3-Setup.exe",
                "LumiaKey-Windows-v1.2.3-Setup.exe",
                42,
                "bad",
            ),
        )
    }

    @Test
    fun onlyAcceptsLocalSharedStorageOutsidePrivateAppDirectories() {
        assertNull(DesktopInstallerValidation.validateLocalFolder(
            "com.android.externalstorage.documents",
            "primary:Download/Installers",
        ))
        assertEquals(
            "Choose a folder from local Android shared storage.",
            DesktopInstallerValidation.validateLocalFolder("com.google.drive", "drive:folder"),
        )
        assertEquals(
            "The selected folder path is invalid.",
            DesktopInstallerValidation.validateLocalFolder(
                "com.android.externalstorage.documents",
                "primary:Download/../Documents",
            ),
        )
        assertEquals(
            "Android data and OBB folders cannot be used for installer export.",
            DesktopInstallerValidation.validateLocalFolder(
                "com.android.externalstorage.documents",
                "primary:Android/data/com.example.app",
            ),
        )
    }
}
