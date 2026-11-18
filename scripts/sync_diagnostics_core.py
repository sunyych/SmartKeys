#!/usr/bin/env python3
"""Synchronize only the dependency-free diagnostics runtime into standalone Lite."""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'packages' / 'diagnostics_core'
TARGET = ROOT / 'apps' / 'bluetooth' / 'packages' / 'diagnostics_core'

def expected_files():
    for item in (SOURCE / 'lib').rglob('*.dart'):
        yield item.relative_to(SOURCE), item.read_bytes()
    yield Path('README.md'), (SOURCE / 'README.md').read_bytes()
    metadata = (SOURCE / 'pubspec.yaml').read_text(encoding='utf-8').split('\ndev_dependencies:', 1)[0].rstrip() + '\n'
    yield Path('pubspec.yaml'), metadata.encode('utf-8')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--full-only', action='store_true', help='Validate only the canonical runtime in a Full-only source export; never create Lite.')
    args = parser.parse_args()
    expected = dict(expected_files())
    for relative, contents in expected.items():
        text = contents.decode('utf-8')
        if relative.suffix == '.dart':
            references = re.findall(r"(?:import|export|part)\s+['\"]([^'\"]+)['\"]", text)
            if any(reference not in {'dart:convert', 'dart:math'} for reference in references):
                raise SystemExit('Diagnostics runtime must have zero platform/network dependencies.')
        if relative.name == 'pubspec.yaml' and re.search(r'^dependencies:', text, re.MULTILINE):
            raise SystemExit('Diagnostics runtime must have zero runtime dependencies.')
        if args.full_only:
            continue
        target = TARGET / relative
        if args.check:
            if not target.is_file() or target.read_bytes() != contents:
                raise SystemExit(f'Out-of-sync diagnostics vendor: {relative}')
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
    if args.full_only:
        print(f'Canonical diagnostics runtime checked: {len(expected)} production files (Full-only export)')
        return
    actual = {p.relative_to(TARGET) for p in TARGET.rglob('*') if p.is_file()} if TARGET.exists() else set()
    if actual != set(expected):
        raise SystemExit('Unexpected files in the production-only diagnostics vendor.')
    print(f'Diagnostics vendor checked: {len(expected)} production files')

if __name__ == '__main__':
    main()
