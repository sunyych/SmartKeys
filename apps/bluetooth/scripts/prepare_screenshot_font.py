#!/usr/bin/env python3
"""Prepare a pinned official Noto font for screenshot CI; no runtime dependency."""
from __future__ import annotations
import argparse
import hashlib
import os
from pathlib import Path
import tempfile
import time
import urllib.error
import urllib.request

# Verified against the official GitHub commit and contents API on 2026-11-17.
# https://github.com/notofonts/noto-cjk/commit/f8d157532fbfaeda587e826d4cd5b21a49186f7c
# Source license: https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/LICENSE
COMMIT = 'f8d157532fbfaeda587e826d4cd5b21a49186f7c'
FONT_URL = f'https://raw.githubusercontent.com/notofonts/noto-cjk/{COMMIT}/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf'
FONT_SHA256 = '2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b'
FONT_BYTES = 16437364
SOCKET_TIMEOUT_SECONDS = 15
ATTEMPT_TIMEOUT_SECONDS = 60
ATTEMPTS = 3

class FontIntegrityError(ValueError):
    pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, target):
        raise FontIntegrityError('Unexpected font redirect.')

def validate_file(path: Path) -> bool:
    if not path.is_file() or path.is_symlink() or path.stat().st_size != FONT_BYTES:
        return False
    digest = hashlib.sha256()
    with path.open('rb') as source:
        if source.read(4) != b'OTTO':
            return False
        source.seek(0)
        for chunk in iter(lambda: source.read(65536), b''):
            digest.update(chunk)
    return digest.hexdigest() == FONT_SHA256

def download_once(output: Path, *, opener=None, clock=time.monotonic) -> None:
    opener = opener or urllib.request.build_opener(NoRedirect())
    deadline = clock() + ATTEMPT_TIMEOUT_SECONDS
    temporary = None
    try:
        request = urllib.request.Request(FONT_URL, headers={'User-Agent': 'LumiaKey-screenshot-CI', 'Accept': 'application/octet-stream'})
        with opener.open(request, timeout=SOCKET_TIMEOUT_SECONDS) as response:
            if response.geturl() != FONT_URL:
                raise FontIntegrityError('Unexpected font source.')
            length = response.headers.get('Content-Length')
            if length is not None and (not length.isdigit() or int(length) != FONT_BYTES):
                raise FontIntegrityError('Unexpected font length.')
            digest = hashlib.sha256()
            size = 0
            header = b''
            with tempfile.NamedTemporaryFile(dir=output.parent, prefix=output.name + '.', suffix='.tmp', delete=False) as stream:
                temporary = Path(stream.name)
                while True:
                    if clock() >= deadline:
                        raise TimeoutError('Font download exceeded its attempt deadline.')
                    # read1 returns after one socket read so a slow trickle cannot
                    # hold a full read(65536) beyond the total attempt deadline.
                    chunk = response.read1(65536)
                    if not chunk:
                        break
                    size += len(chunk)
                    if size > FONT_BYTES:
                        raise FontIntegrityError('Font exceeded its fixed byte limit.')
                    header = (header + chunk)[:4]
                    digest.update(chunk)
                    stream.write(chunk)
                stream.flush()
                os.fsync(stream.fileno())
            if size != FONT_BYTES or header != b'OTTO' or digest.hexdigest() != FONT_SHA256:
                raise FontIntegrityError('Font SHA256, size or format mismatch.')
        os.replace(temporary, output)
        temporary = None
    finally:
        if temporary is not None:
            # Delete only the exact file allocated in the intended output folder.
            if temporary.parent.resolve() != output.parent.resolve() or not temporary.name.startswith(output.name + '.'):
                raise RuntimeError('Unexpected temporary font path.')
            temporary.unlink(missing_ok=True)

def prepare(output: Path, *, opener=None, sleeper=time.sleep) -> None:
    if '\n' in str(output) or '\r' in str(output):
        raise ValueError('Invalid output path.')
    if output.is_symlink():
        raise FontIntegrityError('Font output must not be a symlink.')
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        if not validate_file(output):
            raise FontIntegrityError('Existing screenshot font failed validation.')
        return
    for attempt in range(ATTEMPTS):
        try:
            download_once(output, opener=opener)
            return
        except FontIntegrityError:
            raise
        except (OSError, urllib.error.URLError):
            if attempt == ATTEMPTS - 1:
                raise RuntimeError('Pinned screenshot font unavailable after bounded retries.') from None
            sleeper(attempt + 1)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--github-env', type=Path)
    args = parser.parse_args()
    prepare(args.output)
    resolved = args.output.resolve()
    if args.github_env is not None:
        with args.github_env.open('a', encoding='utf-8', newline='\n') as environment:
            environment.write(f'SMARTKEYS_SCREENSHOT_FONT={resolved}\n')
    print(f'Prepared verified Noto CJK screenshot font ({FONT_BYTES} bytes, SHA256 {FONT_SHA256}).')

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(f'Screenshot font preparation failed: {error}') from None
