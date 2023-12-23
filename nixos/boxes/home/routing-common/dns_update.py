#!/usr/bin/env python3
import argparse
import subprocess

import CloudFlare

def main():
    parser = argparse.ArgumentParser(description='Cloudflare DNS update script')
    parser.add_argument('-k', '--api-token-file', help='Cloudflare API token file')
    parser.add_argument('zone', help='Cloudflare Zone')
    parser.add_argument('record', help='Cloudflare record name')
    args = parser.parse_args()

    address = subprocess.check_output(
        ['drill', '-Q', '-p5353', '@127.0.0.1', args.record, 'A'],
        encoding='utf8').strip()

    cf_token = None
    if args.api_token_file:
        with open(args.api_token_file) as f:
            cf_token = f.readline().strip()

    cf = CloudFlare.CloudFlare(token=cf_token)
    zones = cf.zones.get(params={'name': args.zone})
    assert zones, f'Zone {args.zone} not found'
    records = cf.zones.dns_records.get(zones[0]['id'], params={'name': args.record})
    assert records, f'Record {args.record} not found in zone {args.zone}'

    print(f'Updating {args.record} -> {address}')
    cf.zones.dns_records.patch(
        zones[0]['id'], records[0]['id'],
        data={'type': 'A', 'name': args.record, 'content': address})

if __name__ == '__main__':
    main()
