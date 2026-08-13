import argparse
import json
import os
import re
import sys
import time
import uuid
from pathlib import Path


SIZE_RE = re.compile(r'^([0-9]+(?:\.[0-9]+)?)\s*([kmgt]?i?b?)?$', re.I)
DURATION_RE = re.compile(r'^([0-9]+(?:\.[0-9]+)?)\s*(ms|s|m|h)?$', re.I)


def parse_size(value):
    match = SIZE_RE.match(value)
    if not match:
        raise argparse.ArgumentTypeError(f'invalid size: {value!r}')

    number = float(match.group(1))
    suffix = (match.group(2) or 'b').lower().removesuffix('b').removesuffix('i')
    powers = {'': 0, 'k': 1, 'm': 2, 'g': 3, 't': 4}
    size = round(number * 1024 ** powers[suffix])
    if size <= 0:
        raise argparse.ArgumentTypeError('size must be greater than zero')
    return size


def parse_duration(value):
    match = DURATION_RE.match(value)
    if not match:
        raise argparse.ArgumentTypeError(f'invalid duration: {value!r}')

    number = float(match.group(1))
    suffix = (match.group(2) or 's').lower()
    factors = {'ms': 1, 's': 1000, 'm': 60_000, 'h': 3_600_000}
    return round(number * factors[suffix])


def format_size(size):
    for suffix in ('TiB', 'GiB', 'MiB', 'KiB'):
        unit = 1024 ** {'KiB': 1, 'MiB': 2, 'GiB': 3, 'TiB': 4}[suffix]
        if size >= unit:
            return f'{size / unit:.2f} {suffix}'
    return f'{size} B'


def runtime_root():
    runtime_dir = os.environ.get('XDG_RUNTIME_DIR')
    if not runtime_dir or not os.path.isabs(runtime_dir):
        raise RuntimeError('XDG_RUNTIME_DIR is not set to an absolute path')
    return Path(runtime_dir) / 'firefox-memory-control'


def main():
    parser = argparse.ArgumentParser(
        description='Ask a running memory-controlled Firefox to unload tabs'
    )
    parser.add_argument('size', type=parse_size, help='desired reclaim amount, for example 2G')
    parser.add_argument(
        '--min-inactive',
        type=parse_duration,
        default=0,
        metavar='DURATION',
        help='only unload tabs inactive for this long (default: 0s)',
    )
    parser.add_argument(
        '--timeout',
        type=float,
        default=60,
        metavar='SECONDS',
        help='maximum time to wait for Firefox (default: 60)',
    )
    args = parser.parse_args()

    root = runtime_root()
    requests = root / 'requests'
    responses = root / 'responses'
    requests.mkdir(mode=0o700, parents=True, exist_ok=True)
    responses.mkdir(mode=0o700, parents=True, exist_ok=True)

    request_id = str(uuid.uuid4())
    request_path = requests / f'{request_id}.json'
    temporary_path = requests / f'.{request_id}.{os.getpid()}.tmp'
    response_path = responses / f'{request_id}.json'
    request = {
        'id': request_id,
        'targetBytes': args.size,
        'minInactiveMs': args.min_inactive,
    }

    temporary_path.write_text(json.dumps(request), encoding='utf-8')
    os.chmod(temporary_path, 0o600)
    temporary_path.replace(request_path)

    deadline = time.monotonic() + args.timeout
    try:
        while time.monotonic() < deadline:
            try:
                response = json.loads(response_path.read_text(encoding='utf-8'))
                break
            except FileNotFoundError:
                time.sleep(0.1)
        else:
            raise RuntimeError(
                'timed out waiting for Firefox; start Firefox from the '
                'firefox-memory-control package'
            )
    finally:
        request_path.unlink(missing_ok=True)

    response_path.unlink(missing_ok=True)
    if 'error' in response:
        raise RuntimeError(response['error'])

    unloaded_tabs = response['unloadedTabs']
    estimated_bytes = response['estimatedBytes']
    observed_bytes = response['observedBytes']
    target_bytes = response['targetBytes']
    print(
        f'unloaded {unloaded_tabs} tab(s); '
        f'Firefox estimated {format_size(estimated_bytes)} reclaimable; '
        f'MemAvailable increased by {format_size(observed_bytes)}'
    )
    if not response['reachedTarget']:
        print(
            f'could not reach the requested {format_size(target_bytes)}',
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        print(f'firefox-free-memory: {error}', file=sys.stderr)
        sys.exit(1)
