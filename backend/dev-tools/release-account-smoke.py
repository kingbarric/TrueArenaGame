#!/usr/bin/env python3
"""Exercise push registration races and account deletion using disposable guests.

Requires an explicit deployed API base (e.g. https://host/test). Does not send
notifications, use existing accounts, or print tokens. Removes its guests in finally.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import urllib.error
import urllib.request
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base', required=True)
args = parser.parse_args()
base = args.base.rstrip('/') + '/api/v1'
created = []


def call(method, path, data=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(
        base + path, method=method, headers=headers,
        data=None if data is None else json.dumps(data).encode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        return error.code, None


try:
    for _ in range(2):
        status, guest = call('POST', '/auth/guest', {
            'deviceId': 'release-smoke-' + str(uuid.uuid4()),
            'displayName': 'Release smoke check'})
        assert status == 200 and guest['user']['isGuest'], 'Guest setup failed'
        created.append(guest)

    # This is an intentionally invalid FCM token, never used for a send.
    push = {'platform': 'android', 'token': 'release-smoke-' + str(uuid.uuid4())}
    with ThreadPoolExecutor(max_workers=16) as workers:
        results = list(workers.map(lambda index: call(
            'POST', '/devices/token', push,
            created[index % 2]['accessToken'])[0], range(24)))
    assert results == [201] * 24, 'Concurrent registration failed: ' + str(results)
    assert call('POST', '/devices/token', push, created[1]['accessToken'])[0] == 201
    assert call('DELETE', '/devices/token', {'token': push['token']},
                created[0]['accessToken'])[0] == 200

    for guest in created:
        token = guest['accessToken']
        assert call('DELETE', '/me/account', {'confirmed': False}, token)[0] == 400
        assert call('GET', '/me', token=token)[0] == 200
        assert call('DELETE', '/me/account', {'confirmed': True}, token)[0] == 204
        assert call('GET', '/me', token=token)[0] == 401
        assert call('POST', '/auth/refresh', {
            'refreshToken': guest['refreshToken']})[0] == 401
    print(json.dumps({'passed': True, 'concurrentRegistrations': len(results),
                      'accountSwitchPassed': True, 'confirmationRequired': True,
                      'deletedAccessAndRefreshRejected': True,
                      'disposableAccountsRemoved': len(created)}, indent=2))
finally:
    for guest in created:
        status, _ = call('DELETE', '/me/account', {'confirmed': True},
                         guest['accessToken'])
        assert status in (204, 401), 'Disposable guest cleanup failed'
