const { test } = require('node:test');
const assert = require('node:assert/strict');
require('../src/web/json.js');
const codec = globalThis.MockJSON;

test('keeps i64 values, floating types, and exponent forms when editing JSON', () => {
  const encoded = codec.stringify(codec.parse('{"id":9223372036854775807,"float":1.0,"exp":1e2,"zero":-0,"nested":[null,true,1.23]}'));
  assert.match(encoded, /9223372036854775807/);
  assert.match(encoded, /"float": 1\.0/);
  assert.match(encoded, /"exp": 1e2/);
  assert.match(encoded, /"zero": -0/);
  assert.equal(codec.stringify(codec.parse(encoded)), encoded);
});
test('handles escaped text and prototype-like object keys without corruption', () => {
  const text = '{"__proto__":{"safe":true},"text":"a\\\"b\\\\c\\n中文","array":[{"x":1},false]}';
  assert.deepEqual(JSON.parse(codec.stringify(codec.parse(text))), JSON.parse(text));
  assert.equal({}.safe, undefined);
});
test('rejects malformed JSON and exposes numbers separately from objects', () => {
  assert.throws(() => codec.parse('{"a":1,}'));
  assert.equal(codec.isNumber(codec.parse('1.0')), true);
  assert.equal(codec.isNumber(codec.parse('{}')), false);
  assert.equal(codec.parse('200'), 200);
});
