#!/usr/bin/env python3
"""Reject Full release APKs whose packaged Dart AOT predates required UI.

Version metadata and new assets cannot prove that Gradle merged the new
libapp.so. This execution-free, standard-library guard checks the actual ZIP
members for each expected ABI. It does not verify signatures, metadata,
complete source equivalence, or runtime behavior. Debug kernel APKs are not
AOT artifacts and must not use this check.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import zipfile

ABI_HEADERS = {'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183), 'x86_64': (2, 62)}
REQUIRED_MARKERS = (b'regular-header-controls', b'regular-brand-icon', b'app-library-catalog')
MAX_APK_BYTES = 512 * 1024 * 1024
MAX_LIBRARY_BYTES = 64 * 1024 * 1024
MAX_ENTRIES = 4096
CHUNK_BYTES = 128 * 1024


class VerificationError(ValueError):
    pass


def _library(archive, member, abi):
    if member.file_size < 20 or member.file_size > MAX_LIBRARY_BYTES:
        raise VerificationError(f'{abi}: AOT member exceeds bounds or is truncated')
    if member.flag_bits & 1 or member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        raise VerificationError(f'{abi}: unsupported AOT ZIP encoding')
    found = set()
    digest = hashlib.sha256()
    overlap = max(map(len, REQUIRED_MARKERS)) - 1
    tail, header, size = b'', b'', 0
    with archive.open(member) as source:
        while chunk := source.read(CHUNK_BYTES):
            size += len(chunk)
            if size > MAX_LIBRARY_BYTES:
                raise VerificationError(f'{abi}: decompressed AOT exceeds bounds')
            if not header:
                header = chunk[:20]
                expected_class, machine = ABI_HEADERS[abi]
                if (len(header) < 20 or header[:4] != b'\x7fELF' or
                        header[4] != expected_class or header[5] != 1 or
                        struct.unpack_from('<H', header, 18)[0] != machine):
                    raise VerificationError(f'{abi}: expected matching little-endian ELF AOT')
            window = tail + chunk
            found.update(marker for marker in REQUIRED_MARKERS if marker in window)
            tail = window[-overlap:]
            digest.update(chunk)
    if size != member.file_size:
        raise VerificationError(f'{abi}: incomplete AOT member')
    missing = [marker.decode('ascii') for marker in REQUIRED_MARKERS if marker not in found]
    if missing:
        raise VerificationError(f'{abi}: packaged Dart AOT is missing required Full UI markers: {", ".join(missing)}')
    return {'abi': abi, 'bytes': size, 'sha256': digest.hexdigest()}


def verify_full_apk(path, expected_abis=None):
    abis = tuple(expected_abis or ABI_HEADERS)
    if not abis or len(abis) != len(set(abis)) or any(abi not in ABI_HEADERS for abi in abis):
        raise VerificationError('Expected ABI list must contain distinct supported Android ABIs')
    path = Path(path)
    if not path.is_file() or not 0 < path.stat().st_size <= MAX_APK_BYTES:
        raise VerificationError('APK is missing, empty, or exceeds the input bound')
    try:
        with path.open('rb') as source:
            with zipfile.ZipFile(source) as archive:
                members = archive.infolist()
                if len(members) > MAX_ENTRIES:
                    raise VerificationError('APK has too many ZIP entries')
                by_name = {member.filename: member for member in members}
                if len(by_name) != len(members):
                    raise VerificationError('APK contains duplicate ZIP member names')
                missing = [abi for abi in abis if f'lib/{abi}/libapp.so' not in by_name]
                if missing:
                    raise VerificationError('Expected release AOT libapp.so is missing for: ' + ', '.join(missing) + '; debug kernel APKs are not supported')
                actual_abis = {name.split('/')[1] for name in by_name if name.startswith('lib/') and name.endswith('/libapp.so') and len(name.split('/')) == 3}
                if actual_abis != set(abis):
                    raise VerificationError('Packaged AOT ABI set differs from the explicitly expected ABI set')
                libraries = [_library(archive, by_name[f'lib/{abi}/libapp.so'], abi) for abi in abis]
            source.seek(0)
            digest = hashlib.sha256()
            while chunk := source.read(CHUNK_BYTES):
                digest.update(chunk)
        return {'verified': True, 'kind': 'full-release-dart-aot', 'apk_sha256': digest.hexdigest(),
                'required_markers': [marker.decode('ascii') for marker in REQUIRED_MARKERS], 'libraries': libraries}
    except (OSError, zipfile.BadZipFile, RuntimeError, EOFError) as error:
        raise VerificationError('APK or its AOT members could not be read safely') from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--abi', action='append', choices=tuple(ABI_HEADERS), help='Explicit ABI set for intentionally targeted/split release APKs; default requires all three ABIs')
    args = parser.parse_args()
    try:
        print(json.dumps(verify_full_apk(args.apk, args.abi), indent=2))
    except VerificationError as error:
        print(f'Full release APK verification failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
