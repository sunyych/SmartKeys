import hashlib
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

import verify_full_apk as guard


def synthetic_aot(abi, *, current=True):
    header = bytearray(64)
    header[:4] = b'\x7fELF'
    header[4], header[5] = guard.ABI_HEADERS[abi][0], 1
    struct.pack_into('<H', header, 18, guard.ABI_HEADERS[abi][1])
    return bytes(header) + (b'\0'.join(guard.REQUIRED_MARKERS) if current else b'DESKTOP COMPANION\0Most used')


class FullApkGuardTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.apk = Path(self.directory.name) / 'full.apk'

    def make_apk(self, abis=None, *, current=True, overrides=None):
        with zipfile.ZipFile(self.apk, 'w', zipfile.ZIP_DEFLATED) as archive:
            # A new resource and native version-looking data must not hide old AOT.
            archive.writestr('assets/flutter_assets/assets/app_icon/app_icon_source.png', b'new image')
            archive.writestr('AndroidManifest.xml', b'versionName=1.7.0;versionCode=9')
            for abi in abis or guard.ABI_HEADERS:
                archive.writestr(f'lib/{abi}/libapp.so', (overrides or {}).get(abi, synthetic_aot(abi, current=current)))

    def test_current_aot_in_every_expected_abi_reports_actual_hashes(self):
        self.make_apk()
        result = guard.verify_full_apk(self.apk)
        self.assertTrue(result['verified'])
        self.assertEqual(result['apk_sha256'], hashlib.sha256(self.apk.read_bytes()).hexdigest())
        self.assertEqual({item['abi'] for item in result['libraries']}, set(guard.ABI_HEADERS))

    def test_new_metadata_and_assets_with_old_aot_are_rejected(self):
        self.make_apk(current=False)
        with self.assertRaisesRegex(guard.VerificationError, 'missing required Full UI markers'):
            guard.verify_full_apk(self.apk)

    def test_one_stale_abi_is_rejected_even_when_other_abis_are_current(self):
        self.make_apk(overrides={'arm64-v8a': synthetic_aot('arm64-v8a', current=False)})
        with self.assertRaisesRegex(guard.VerificationError, 'arm64-v8a.*missing required'):
            guard.verify_full_apk(self.apk)

    def test_missing_abi_is_rejected_unless_intentionally_selected(self):
        self.make_apk(['arm64-v8a'])
        with self.assertRaisesRegex(guard.VerificationError, 'missing for'):
            guard.verify_full_apk(self.apk)
        self.assertTrue(guard.verify_full_apk(self.apk, ['arm64-v8a'])['verified'])

    def test_duplicate_member_is_rejected(self):
        self.make_apk()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.apk, 'a') as archive:
                archive.writestr('lib/arm64-v8a/libapp.so', synthetic_aot('arm64-v8a'))
        with self.assertRaisesRegex(guard.VerificationError, 'duplicate'):
            guard.verify_full_apk(self.apk)

    def test_oversized_file_and_decompressed_member_are_rejected(self):
        self.make_apk()
        with patch.object(guard, 'MAX_APK_BYTES', 1):
            with self.assertRaisesRegex(guard.VerificationError, 'input bound'):
                guard.verify_full_apk(self.apk)
        with patch.object(guard, 'MAX_LIBRARY_BYTES', 20):
            with self.assertRaisesRegex(guard.VerificationError, 'member exceeds bounds'):
                guard.verify_full_apk(self.apk)

    def test_wrong_elf_architecture_and_non_elf_are_rejected(self):
        for data in [synthetic_aot('x86_64'), b'not an ELF' + b'\0'.join(guard.REQUIRED_MARKERS)]:
            self.make_apk(overrides={'arm64-v8a': data})
            with self.assertRaisesRegex(guard.VerificationError, 'matching little-endian ELF'):
                guard.verify_full_apk(self.apk)

    def test_debug_kernel_apk_is_explicitly_rejected(self):
        with zipfile.ZipFile(self.apk, 'w') as archive:
            archive.writestr('assets/flutter_assets/kernel_blob.bin', b'\0'.join(guard.REQUIRED_MARKERS))
        with self.assertRaisesRegex(guard.VerificationError, 'debug kernel APKs are not supported'):
            guard.verify_full_apk(self.apk)

    def test_markers_crossing_stream_chunk_boundaries_are_detected(self):
        self.make_apk()
        with patch.object(guard, 'CHUNK_BYTES', 67):
            self.assertTrue(guard.verify_full_apk(self.apk)['verified'])


if __name__ == '__main__':
    unittest.main()
