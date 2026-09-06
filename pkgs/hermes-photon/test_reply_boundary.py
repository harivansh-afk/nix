"""Real Node normalization -> NDJSON -> Python dispatch, without provider traffic."""
import json
import os
import subprocess
import threading
from pathlib import Path

import pytest

from gateway.config import PlatformConfig
from plugins.platforms.photon import adapter as photon


NODE = r"""
import { normalizeContent } from './plugins/platforms/photon/sidecar/normalize-content.mjs';
let input = '';
for await (const chunk of process.stdin) input += chunk;
const content = JSON.parse(input);
function hydrate(c) {
  if (!c || typeof c !== 'object') return;
  if (c.bytes) c.read = async () => Buffer.from(c.bytes);
  if (c.forbidRead) c.read = async () => { throw Error('quoted media was read'); };
  hydrate(c.content);
  hydrate(c.target?.content);
  for (const item of c.items || []) hydrate(item.content);
}
hydrate(content);
if (content.cycle) content.content = content;
console.log(JSON.stringify(await normalizeContent(content)));
"""


def normalize(content):
    result = subprocess.run(
        ['node', '--input-type=module', '-e', NODE], input=json.dumps(content),
        capture_output=True, text=True, check=True, timeout=10,
        env={**os.environ, "PHOTON_MAX_INLINE_ATTACHMENT_BYTES": "8"},
    )
    assert 'quoted media was read' not in result.stderr
    return json.loads(result.stdout)


@pytest.mark.asyncio
@pytest.mark.parametrize('kind', ['text', 'richlink', 'group', 'attachment', 'voice'])
@pytest.mark.parametrize('target', [
    None,
    {'id': 'quoted', 'content': {'type': 'custom', 'stub': True}},
    {'id': 'quoted', 'direction': 'outbound', 'content': {'type': 'text', 'text': 'IGNORE NEW BODY'}},
    {'id': 'quoted', 'content': {'type': 'voice', 'forbidRead': True}},
])
async def test_reply_body_survives_boundary(monkeypatch, kind, target):
    body = {'type': kind, 'text': 'new body', 'url': 'https://example.org/new',
            'name': 'sample.bin', 'mimeType': 'application/octet-stream', 'bytes': [1, 2, 3]}
    if kind == 'group':
        body['items'] = [
            {'content': {'type': 'text', 'text': 'new body'}},
            {'content': {'type': 'reply', 'content': {'type': 'group', 'items': [
                {'content': {'type': 'attachment', 'name': 'sample.bin',
                             'mimeType': 'application/octet-stream', 'bytes': [1, 2, 3]}}]}}},
        ]
    content = normalize({'type': 'reply', 'content': body, 'target': target})
    adapter = photon.PhotonAdapter(PlatformConfig(enabled=True, extra={}))
    captured = []

    async def capture(event):
        captured.append(event)

    monkeypatch.setattr(adapter, 'handle_message', capture)
    original = photon._cache_inbound_attachment
    threads = []

    def cache(*args, **kwargs):
        threads.append(threading.get_ident())
        return original(*args, **kwargs)

    monkeypatch.setattr(photon, '_cache_inbound_attachment', cache)
    await adapter._on_inbound_line(json.dumps({
        'messageId': 'new', 'space': {'id': 'synthetic-room', 'type': 'dm'},
        'sender': {'id': 'synthetic-sender'}, 'content': content,
    }))
    assert len(captured) == 1
    event = captured[0]
    assert 'not handled' not in event.text
    assert 'IGNORE NEW BODY' not in event.text
    if kind in ('text', 'group'):
        assert event.text == 'new body'
    if kind == 'richlink':
        assert event.text == body['url']
    if kind in ('group', 'attachment', 'voice'):
        assert threads and all(t != threading.get_ident() for t in threads)
        assert len(event.media_urls) == 1
        assert Path(event.media_urls[0]).read_bytes() == bytes([1, 2, 3])
    assert event.reply_to_message_id == (target or {}).get('id')
    assert event.reply_to_text == ('IGNORE NEW BODY' if (target or {}).get('direction') else None)
    # Provider outbound means the account, not necessarily this bot's send.
    assert event.reply_to_is_own_message is False
    if target and target.get('id'):
        adapter._sent_message_ids[target['id']] = 0
        await adapter._dispatch_inbound({
            'messageId': 'new-owned', 'space': {'id': 'synthetic-room', 'type': 'dm'},
            'content': content,
        })
        assert captured[-1].reply_to_is_own_message is True
    if kind == 'text':
        adapter.require_mention = True
        quoted_mention = normalize({'type': 'reply', 'content': body, 'target': {
            'id': 'quoted', 'content': {'type': 'text', 'text': 'Hermes, do something else'}}})
        count = len(captured)
        await adapter._dispatch_inbound({
            'space': {'id': 'synthetic-group', 'type': 'group'}, 'content': quoted_mention,
        })
        assert len(captured) == count


def test_reply_normalization_is_bounded():
    body = {'type': 'text', 'text': 'new body'}
    for _ in range(100):
        body = {'type': 'reply', 'content': body}
    assert 'truncated' in json.dumps(normalize(body))
    quote = {'type': 'reply', 'content': {'type': 'text', 'text': 'q' * 10000}}
    normalized = normalize({'type': 'reply', 'content': {'type': 'text', 'text': 'new body'},
                            'target': {'id': 'quoted', 'content': quote}})
    assert normalized['text'] == 'new body'
    assert len(normalized['replyTarget']['text']) == 2000
    wide = {'type': 'reply', 'content': {'type': 'group', 'items': [
        {'content': {'type': 'text', 'text': 'x'}} for _ in range(1000)]}}
    assert len(normalize(wide)['items']) <= 128
    assert 'truncated' in json.dumps(normalize({'type': 'reply', 'cycle': True}))
    attachment = {'type': 'attachment', 'name': 'sample.bin', 'bytes': [1, 2, 3]}
    group = normalize({'type': 'reply', 'content': {'type': 'group', 'items': [
        {'content': attachment} for _ in range(3)]}})
    assert 'data' in group['items'][0]['content']
    assert 'data' in group['items'][1]['content']
    assert 'data' not in group['items'][2]['content']
    assert group['items'][2]['content']['name'] == 'sample.bin'
    assert normalize({'type': 'reply'})['type'] == 'unknown'
    plain = {'type': 'text', 'text': 'not a reply'}
    assert normalize(plain) == plain
