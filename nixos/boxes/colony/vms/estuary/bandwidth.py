#!/usr/bin/env python
import time
import datetime
import sys
import os
import subprocess
import json
import signal
import shlex

INTERVAL = 5 * 60
HZ = 1000
LATENCY = '300ms'

def end_of_month(dt: datetime.datetime):
    return datetime.datetime(dt.year, dt.month + 1 if dt.month != 12 else 1, 1) - datetime.timedelta(seconds=1)

def start_of_month(dt: datetime.datetime):
    return datetime.datetime(dt.year, dt.month, 1)

def month_seconds(dt: datetime.datetime):
    return (end_of_month(dt) - start_of_month(dt)).total_seconds()

def month_fraction(dt: datetime.datetime):
    return (dt - start_of_month(dt)).total_seconds() / month_seconds(dt)

def main():
    if len(sys.argv) != 4:
        print(f'usage: {sys.argv[0]} <interfaces> <95% limit mbit> <hi limit mbit>')
        sys.exit(1)

    ifaces = sys.argv[1].split(',')
    lo = int(sys.argv[2])
    hi = int(sys.argv[3])

    cutoff = int((lo / 8) * 1024 * 1024 * INTERVAL)

    basedir = os.environ['STATE_DIRECTORY']

    def sig_handler(signum, frame):
        sys.exit(0)
    signal.signal(signal.SIGTERM, sig_handler)

    last_total = 0
    while True:
        now = datetime.datetime.now()

        total = 0
        for n in ifaces:
            output = subprocess.check_output(['ip', '-j', '-s', 'link', 'show', 'dev', n], encoding='utf-8')
            stats = json.loads(output)
            total += stats[0]['stats64']['tx']['bytes']

        if last_total == 0:
            last_total = total

        data_file = os.path.join(basedir, str(now.year), f'{now.month}.json')
        os.makedirs(os.path.dirname(data_file), exist_ok=True)

        data = {
            'hi_fraction_used': 0.0,
        }
        if os.path.exists(data_file):
            with open(data_file, 'r') as f:
                data = json.load(f)

        if total - last_total > cutoff:
            print(f'used more than {lo}mbps over the last {INTERVAL}s')
            data['hi_fraction_used'] += INTERVAL / month_seconds(now)

        limit = hi
        mf = month_fraction(now)
        if data['hi_fraction_used'] >= mf:
            print(f"warning: used too many 5% buckets so far {data['hi_fraction_used']} and we are {mf} into the month); applying bandwidth limit")
            limit = lo

        with open(data_file, 'w') as f:
            json.dump(data, f)

        qdisc_args = ['rate', f'{limit}mbit', 'burst', str(int(((limit*1000*1000)/HZ/8) * 4)), 'latency', LATENCY]
        for n in ifaces:
            subprocess.check_call(['tc', 'qdisc', 'change', 'dev', n, 'root', 'tbf'] + qdisc_args)

        last_total = total
        time.sleep(INTERVAL)

if __name__ == '__main__':
	main()
