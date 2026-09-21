import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateTurn, FALLBACK_TURN, DEFAULT_ASSET_ALLOWLIST, loadAssetAllowlist, checkText, fallbackTurn } from '../src/turn_validator.js';
import { REPO_ROOT } from '../src/config.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LOCAL_FIXTURES = path.join(HERE, 'fixtures', 'turn_fixtures.json');
const SHARED_FIXTURES = path.join(REPO_ROOT, 'game', 'content', 'tutor', 'turn_fixtures.json');

/** @param {string} file */
function runFixtureFile(file, label) {
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  const cases = Array.isArray(data) ? data : data.cases;
  assert.ok(Array.isArray(cases) && cases.length >= 12, `${label}: expected >= 12 cases`);
  for (const c of cases) {
    test(`${label}: ${c.name}`, () => {
      const r = validateTurn(c.input, { allowlist: DEFAULT_ASSET_ALLOWLIST });
      if (c.expect === 'valid') {
        assert.equal(r.ok, true, `expected valid, got reasons ${r.reasons.join(',')}`);
        for (const [k, v] of Object.entries(c.normalized ?? {})) assert.deepEqual(r.turn[k], v, `normalized.${k}`);
      } else {
        assert.equal(r.ok, false, 'expected fallback');
        assert.deepEqual(r.turn, fallbackTurn());
        if (c.reasonPrefix) assert.ok(r.reasons.some((x) => x.startsWith(c.reasonPrefix)), `reasons ${r.reasons.join(',')} should include ${c.reasonPrefix}`);
      }
    });
  }
}

runFixtureFile(LOCAL_FIXTURES, 'local fixtures');
if (fs.existsSync(SHARED_FIXTURES)) runFixtureFile(SHARED_FIXTURES, 'shared fixtures');
else test('shared fixtures file not present yet (game/content/tutor/turn_fixtures.json) - skipped', () => {});

test('fallback turn matches the contract exactly', () => {
  assert.deepEqual({ ...FALLBACK_TURN, visual: { ...FALLBACK_TURN.visual } }, { speech: "Let's try together!", emotion: 'encouraging', gesture: 'tilt', visual: { type: 'none' }, lessonAction: 'retry' });
  assert.equal(validateTurn(FALLBACK_TURN).ok, true);
});

test('truth table: every enum value is accepted and one-off values are not', () => {
  const base = { speech: 'Hi!', emotion: 'happy', gesture: 'nod', visual: { type: 'none' }, lessonAction: 'retry' };
  for (const emotion of ['neutral', 'listening', 'thinking', 'happy', 'encouraging', 'smile']) assert.ok(validateTurn({ ...base, emotion }).ok, emotion);
  for (const gesture of ['none', 'nod', 'tilt', 'point', 'clap', 'wave', 'thumbsUp', 'celebrate', 'listening', 'thinking', 'encourage']) assert.ok(validateTurn({ ...base, gesture }).ok, gesture);
  for (const lessonAction of ['next_question', 'retry', 'give_hint', 'complete', 'end_session']) assert.ok(validateTurn({ ...base, lessonAction }).ok, lessonAction);
  for (const id of DEFAULT_ASSET_ALLOWLIST) assert.ok(validateTurn({ ...base, visual: { type: 'flashcard', assetId: id } }).ok, id);
  assert.equal(validateTurn({ ...base, emotion: 'Happy' }).ok, false);
  assert.equal(validateTurn({ ...base, gesture: 'NOD' }).ok, false);
  assert.equal(validateTurn({ ...base, lessonAction: 'next' }).ok, false);
  assert.equal(validateTurn({ ...base, visual: { type: 'gif', assetId: 'cat' } }).ok, false);
  assert.equal(validateTurn({ ...base, visual: { type: 'none', assetId: 'not_allowed' } }).ok, false);
});

test('checkText edge cases', () => {
  assert.deepEqual(checkText('a'.repeat(160), 'speech', 160, true), []);
  assert.deepEqual(checkText('a'.repeat(161), 'speech', 160, true), ['speech:too_long']);
  assert.deepEqual(checkText('12345678901234567890', 'speech', 160, true), []); // exactly 20 digits ok
  assert.deepEqual(checkText('www.example.org', 'speech', 160, true), ['speech:url']);
  assert.deepEqual(checkText('Hello. Nice, right? Yes: "good"!', 'speech', 160, true), []);
  assert.deepEqual(checkText('tab\there', 'speech', 160, true), ['speech:non_ascii']);
  assert.deepEqual(checkText('The cat is kind.', 'speech', 160, true), []); // "kind" contains no banned word
  assert.deepEqual(checkText('hello', 'speech', 160, true), []); // "hell" only matches as a whole word
  assert.deepEqual(checkText('   ', 'speech', 160, true), ['speech:required']);
  assert.deepEqual(checkText(undefined, 'nextQuestion', 120, false), []);
});

test('allowlist loader falls back to the contract list when the file is missing', () => {
  const r = loadAssetAllowlist('/nonexistent/assets_allowlist.json');
  assert.equal(r.source, 'default');
  assert.deepEqual(r.ids, [...DEFAULT_ASSET_ALLOWLIST]);
});
