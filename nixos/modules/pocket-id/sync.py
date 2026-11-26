"""Create and update Pocket ID user groups and OIDC clients from a JSON spec.

Usage: pocket-id-sync <spec.json> <base URL>

Credentials come from systemd's $CREDENTIALS_DIRECTORY: `api-key` (the static API key) and
`client-<id>` (each confidential client's secret). Hashes of the secrets that were set are
kept in $STATE_DIRECTORY, since Pocket ID only shows a secret's first few characters.
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Fields of a client that the update endpoint accepts
CLIENT_FIELDS = [
    'name', 'description', 'callbackURLs', 'logoutCallbackURLs', 'backchannelLogoutURL',
    'isPublic', 'pkceEnabled', 'requiresReauthentication', 'requiresPushedAuthorizationRequests',
    'skipConsent', 'credentials', 'launchURL', 'hasLogo', 'hasDarkLogo', 'isGroupRestricted',
    'accessTokenDurationMinutes', 'refreshTokenDurationMinutes',
]
SECRET_PREFIX_LENGTH = 4


class NotFound(Exception):
    pass


class API:
    def __init__(self, base, key):
        self.base = base
        self.key = key

    def request(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            f'{self.base}/api{path}', data=data, method=method,
            headers={'X-API-Key': self.key, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req) as res:
                content = res.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFound(path) from e
            raise RuntimeError(f'{method} {path}: HTTP {e.code}: {e.read().decode()}') from e

        return json.loads(content) if content else None

    def wait(self, timeout=60):
        for _ in range(timeout):
            try:
                with urllib.request.urlopen(f'{self.base}/healthz'):
                    return
            except OSError:
                time.sleep(1)
        raise RuntimeError('Pocket ID did not become healthy')


def read_secret(path, key):
    text = path.read_text()
    if key is None:
        return text.rstrip('\n')

    # A plain env file, as `slop secret` writes it
    value = None
    for line in text.splitlines():
        name, sep, v = line.removeprefix('export ').partition('=')
        if sep and name == key:
            value = v
    if value is None:
        raise RuntimeError(f'{path} has no {key}')
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    return value


def sync_groups(api, groups):
    existing = {g['name']: g for g in api.request('GET', '/user-groups?pagination[limit]=1000')['data']}

    for group in groups:
        current = existing.get(group['name'])
        if current is None:
            print(f"Creating group {group['name']}")
            api.request('POST', '/user-groups', group)
        elif current['friendlyName'] != group['friendlyName']:
            print(f"Updating group {group['name']}")
            api.request('PUT', f"/user-groups/{current['id']}", group)

    return {g['name']: g['id'] for g in api.request('GET', '/user-groups?pagination[limit]=1000')['data']}


def sync_secret(api, client_id, value, state_dir):
    digest = hashlib.sha256(f'{client_id}\n{value}'.encode()).hexdigest()
    state = state_dir / f'{client_id}.sha256'
    secrets = api.request('GET', f'/oidc/clients/{client_id}/secrets')

    installed = any(s['isActive'] and s['prefix'] == value[:SECRET_PREFIX_LENGTH] for s in secrets)
    if installed and state.exists() and state.read_text() == digest:
        return

    print(f'Setting the secret of client {client_id}')
    new = api.request('POST', f'/oidc/clients/{client_id}/secrets', {'secret': value})
    for s in secrets:
        if s['id'] != new['id']:
            api.request('DELETE', f"/oidc/clients/{client_id}/secrets/{s['id']}")
    state.write_text(digest)


def sync_client(api, client, group_ids, creds, state_dir):
    client_id = client['id']
    settings = client['settings']

    # Update on top of the current client, so fields managed in the UI (like logos) stay
    try:
        current = api.request('GET', f'/oidc/clients/{client_id}')
    except NotFound:
        print(f'Creating client {client_id}')
        api.request('POST', '/oidc/clients', {**settings, 'id': client_id})
    else:
        merged = {**current, **settings}
        api.request('PUT', f'/oidc/clients/{client_id}', {f: merged.get(f) for f in CLIENT_FIELDS})

    unknown = [g for g in client['groups'] if g not in group_ids]
    if unknown:
        raise RuntimeError(f'Client {client_id}: unknown groups {unknown}')
    api.request('PUT', f'/oidc/clients/{client_id}/allowed-user-groups',
                {'userGroupIds': [group_ids[g] for g in client['groups']]})

    if client['secret']:
        value = read_secret(creds / f'client-{client_id}', client['secretKey'])
        sync_secret(api, client_id, value, state_dir)


def main():
    spec = json.loads(Path(sys.argv[1]).read_text())
    creds = Path(os.environ['CREDENTIALS_DIRECTORY'])
    state_dir = Path(os.environ['STATE_DIRECTORY'])

    api = API(sys.argv[2], (creds / 'api-key').read_text().strip())
    api.wait()

    group_ids = sync_groups(api, spec['groups'])
    for client in spec['clients']:
        sync_client(api, client, group_ids, creds, state_dir)


if __name__ == '__main__':
    main()
