#!/usr/bin/env python3
import argparse
import json
import subprocess

import CloudFlare

def main():
    parser = argparse.ArgumentParser(description='Cloudflare DNS update script')
    parser.add_argument('-k', '--api-token-file', help='Cloudflare API token file')
    parser.add_argument('zone', help='Cloudflare Zone')
    parser.add_argument('record', help='Cloudflare record name')
    parser.add_argument('iface', help='Network interface to grab IP from')
    args = parser.parse_args()

    cf_token = None
    if args.api_token_file:
        with open(args.api_token_file) as f:
            cf_token = f.readline().strip()

    cf = CloudFlare.CloudFlare(token=cf_token)
    zones = cf.zones.get(params={'name': args.zone})
    assert zones, f'Zone {args.zone} not found'
    records = cf.zones.dns_records.get(zones[0]['id'], params={'name': args.record})
    assert records, f'Record {args.record} not found in zone {args.zone}'


    ip_info = json.loads(subprocess.check_output(
        ['ip', '-j', 'addr', 'show', 'dev', args.iface], encoding='utf8'))
    for a_info in ip_info[0]['addr_info']:
        if a_info['family'] == 'inet' and a_info['scope'] == 'global':
            address = a_info['local']
            break
    else:
        assert False, f'No usable IP address found on interface {args.iface}'

    print(f'Updating {args.record} -> {address}')
    cf.zones.dns_records.patch(
        zones[0]['id'], records[0]['id'],
        data={'type': 'A', 'name': args.record, 'content': address})

if __name__ == '__main__':
    main()