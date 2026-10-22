import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeRng } from '../src/rng.js';

test('same seed reproduces the same sequence', () => {
  const a = makeRng(20261022);
  const b = makeRng(20261022);
  const seqA = Array.from({ length: 20 }, () => a.nextFloat());
  const seqB = Array.from({ length: 20 }, () => b.nextFloat());
  assert.deepEqual(seqA, seqB);
});

test('different seeds produce different sequences', () => {
  const a = makeRng(1);
  const b = makeRng(2);
  const seqA = Array.from({ length: 10 }, () => a.nextFloat());
  const seqB = Array.from({ length: 10 }, () => b.nextFloat());
  assert.notDeepEqual(seqA, seqB);
});

test('values stay inside their ranges', () => {
  const rng = makeRng(7);
  for (let i = 0; i < 100; i++) {
    const v = rng.nextFloat();
    assert.ok(v >= 0 && v < 1);
    const r = rng.nextRange(5, 9);
    assert.ok(r >= 5 && r < 9);
  }
});
