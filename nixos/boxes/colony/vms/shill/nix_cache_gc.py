#!/usr/bin/env python
import re
import argparse
import configparser
import sys
import signal

import minio

re_filename_filter = re.compile(r'^(\S+\.narinfo|nar\/\S+\.nar\.\S+)$')
re_narinfo_line = re.compile(r'^(\S+): (.*)$')
re_nix_path_hash = re.compile(r'^([0123456789abcdfghijklmnpqrsvwxyz]+)-.+$')

def parse_narinfo(data):
    lines = data.decode('utf-8').split('\n')
    vals = {'_NarInfoSize': len(data)}
    for line in lines:
        m = re_narinfo_line.match(line)
        if not m:
            continue

        key = m.group(1)
        val = m.group(2)

        if key == 'References':
            if not val:
                val = set()
            else:
                refs = val.split(' ')
                val = set()
                for ref in refs:
                    m = re_nix_path_hash.match(ref)
                    assert m
                    val.add(f'{m.group(1)}.narinfo')
        elif key in ('FileSize', 'NarSize'):
            val = int(val)

        vals[key] = val
    return vals

def log(message):
    print(message, file=sys.stderr)
    sys.stderr.flush()

def main():
    def sig_handler(signum, frame):
        sys.exit(0)
    signal.signal(signal.SIGTERM, sig_handler)

    parser = argparse.ArgumentParser(description='"Garbage collect" S3-based Nix cache')
    parser.add_argument('-c', '--config', required=True, action='append', help='config file')
    parser.add_argument('-d', '--dry-run', action='store_true', help="don't actually delete anything")
    parser.add_argument('-v', '--verbose', action='store_true', help="log extra info")

    args = parser.parse_args()

    def verbose(message):
        if args.verbose:
            log(message)

    config = configparser.ConfigParser()
    config.read(args.config)

    gc_thresh = config.getint('gc', 'threshold')*1024*1024
    gc_stop = config.getint('gc', 'stop')*1024*1024
    assert gc_stop < gc_thresh

    s3_special = {'endpoint', 'bucket'}
    s3_ext = dict(filter(lambda i: i[0] not in s3_special, config.items('s3')))
    mio = minio.Minio(config.get('s3', 'endpoint'), **s3_ext)

    bucket = config.get('s3', 'bucket')
    objs = list(filter(lambda o: re_filename_filter.match(o.object_name), mio.list_objects(bucket, recursive=True)))

    total_size = sum(map(lambda o: o.size, objs))
    if total_size < gc_thresh:
        log(f'Cache is only {total_size/1024/1024}MiB, not bothering')
        return
    log(f'Cache is {total_size/1024/1024}MiB, collecting garbage')

    oldest = sorted(objs, key=lambda o: o.last_modified)
    free_size = 0
    i = 0
    to_delete = []
    while free_size < total_size - gc_stop:
        obj = oldest[i]
        free_size += obj.size
        to_delete.append(obj.object_name)
        verbose(f'Deleting {obj.object_name}')
        verbose(f'Up to {free_size/1024/1024}MiB')
        i += 1

    log(f'About to delete {len(to_delete)} NARs / narinfos, total size {free_size/1024/1024}MiB')
    if args.dry_run:
        return

    delete_objs = [minio.deleteobjects.DeleteObject(name) for name in to_delete]
    errors = mio.remove_objects(bucket, delete_objs)
    for err in errors:
        log(f'Error while deleting: {err}')
        sys.exit(1)

    # TODO: Make this smart?
    #narinfos = sorted(filter(lambda o: o.object_name.endswith('.narinfo'), objs), key=lambda o: o.last_modified)
    #narinfos_map = {}
    #def narinfo(name):
    #    if name not in narinfos_map:
    #        try:
    #            resp = mio.get_object(bucket, name)
    #            info = parse_narinfo(resp.read())
    #            narinfos_map[name] = info
    #        finally:
    #            resp.close()
    #            resp.release_conn()
    #    return narinfos_map[name]

    #free_size = 0
    #to_delete = set()
    #to_delete_nars = []
    #def traverse_narinfo(name):
    #    if name in to_delete:
    #        return 0

    #    info = narinfo(name)
    #    verbose(f"Going to delete {name} ({info['URL']}; {info['StorePath']})")
    #    to_delete_nars.append(info['URL'])
    #    size = info['_NarInfoSize'] + info['FileSize']
    #    for ref in info['References']:
    #        if ref == name:
    #            continue
    #        size += traverse_narinfo(ref)

    #    to_delete.add(name)
    #    return size

    #i = 0
    #while free_size < total_size - gc_stop:
    #    obj = narinfos[i]
    #    free_size += traverse_narinfo(obj.object_name)
    #    verbose(f'Up to {free_size/1024/1024}MiB')
    #    i += 1

    #assert len(to_delete_nars) == len(to_delete)
    #log(f'About to delete {len(to_delete)} NARs (and associated narinfos), total size {free_size/1024/1024}MiB')

if __name__ == '__main__':
    main()
