#!/usr/bin/env python3
import argparse
import subprocess

import cloudflare

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
    cf = cloudflare.Cloudflare(api_token=cf_token)

    zones = list(cf.zones.list(name=args.zone))
    assert zones, f'Zone {args.zone} not found'
    assert len(zones) == 1, f'More than one zone found for {args.zone}'
    zone = zones[0]

    records = list(cf.dns.records.list(zone_id=zone.id, name=args.record, type='A'))
    assert records, f'Record {args.record} not found in zone {args.zone}'
    assert len(records) == 1, f'More than one record found for {args.record}'
    record = records[0]

    print(f'Updating {args.record} -> {address}')
    cf.dns.records.edit(
        zone_id=zone.id, dns_record_id=record.id,
        type='A', content=address)

if __name__ == '__main__':
    main()
