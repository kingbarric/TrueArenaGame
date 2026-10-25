import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LookState } from '../src/look-state.ts';

test('saving requires a fully loaded look and rejects failed outfit replacements', async () => {
  const state = new LookState();
  assert.throws(() => state.requireRendered(), /complete look/);
  const first = {body: 'female'};
  await state.apply(first, async () => {});
  assert.equal(state.requireRendered(), first);
  await assert.rejects(state.apply({body: 'male'}, async () => { throw Error('Missing shoe'); }), /Missing shoe/);
  assert.throws(() => state.requireRendered(), /complete look/);
  await state.apply(first, async () => {});
  assert.equal(state.requireRendered(), first);
});

test('a look cannot be saved while its replacement is still loading', async () => {
  const state = new LookState();
  await state.apply({body: 'female'}, async () => {});
  let finish;
  const pending = state.apply({body: 'male'}, () => new Promise(resolve => { finish = resolve; }));
  assert.throws(() => state.requireRendered(), /complete look/);
  finish(); await pending;
  assert.equal(state.requireRendered().body, 'male');
});
