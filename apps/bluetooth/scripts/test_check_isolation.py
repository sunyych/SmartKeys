import io
import unittest
from zipfile import ZipFile

from check_isolation import LITE_SURFACE_MARKERS, verify_packaged_surface


class CompiledSurfaceTests(unittest.TestCase):
    def archive(self, entries):
        stream = io.BytesIO()
        with ZipFile(stream, 'w') as archive:
            for name, payload in entries.items():
                archive.writestr(name, payload)
        stream.seek(0)
        archive = ZipFile(stream)
        self.addCleanup(archive.close)
        return archive

    def binary(self, prefix=b'\x7fELF', markers=LITE_SURFACE_MARKERS):
        return prefix + b'\0'.join(markers) + b'\0' * (1024 * 1024)

    def test_every_release_abi_contains_current_surface(self):
        result = verify_packaged_surface(self.archive({
            'lib/arm64-v8a/libapp.so': self.binary(),
            'lib/armeabi-v7a/libapp.so': self.binary(),
        }))
        self.assertEqual(result['aotAbisVerified'], 2)
        self.assertEqual(result['compiledSurface'], 'AOT')

    def test_one_stale_abi_is_rejected_even_with_new_other_abi(self):
        with self.assertRaisesRegex(ValueError, 'current control surface'):
            verify_packaged_surface(self.archive({
                'lib/arm64-v8a/libapp.so': self.binary(),
                'lib/x86_64/libapp.so': self.binary(markers=LITE_SURFACE_MARKERS[:-1]),
            }))

    def test_png_or_metadata_does_not_substitute_for_aot(self):
        with self.assertRaises(ValueError):
            verify_packaged_surface(self.archive({
                'assets/new_version.txt': b'1.2.0',
                'assets/flutter_assets/assets/app_icons/chrome.png': self.binary(),
            }))

    def test_non_elf_and_small_binary_are_rejected(self):
        for binary in [self.binary(prefix=b'NOTELF'), b'\x7fELF' + b''.join(LITE_SURFACE_MARKERS)]:
            with self.subTest(binary_size=len(binary)), self.assertRaisesRegex(ValueError, 'AOT binary'):
                verify_packaged_surface(self.archive({'lib/arm64-v8a/libapp.so': binary}))

    def test_debug_reports_kernel_not_aot_validation(self):
        result = verify_packaged_surface(self.archive({
            'assets/flutter_assets/kernel_blob.bin': self.binary(prefix=b'KERNEL'),
        }))
        self.assertIn('debug kernel', result['compiledSurface'])
        self.assertEqual(result['aotAbisVerified'], 0)

    def test_stale_debug_kernel_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Debug kernel'):
            verify_packaged_surface(self.archive({
                'assets/flutter_assets/kernel_blob.bin': self.binary(markers=()),
            }))


if __name__ == '__main__':
    unittest.main()
