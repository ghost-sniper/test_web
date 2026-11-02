'use strict';
// Preserve JSON number lexemes: JS Number would round i64 values and turn 1.0
// into 1, which changes the Mock engine's type-sensitive matching semantics.
globalThis.MockJSON = (() => {
  class NumberToken {
    constructor(source) { this.source = source; }
    toString() { return this.source; }
    valueOf() { return Number(this.source); }
  }
  function parse(text) {
    JSON.parse(text); // Validate the complete grammar before scanning tokens.
    let index = 0;
    const whitespace = () => { while (/\s/.test(text[index] || '') && index < text.length) index++; };
    function string() {
      const start = index++;
      while (index < text.length) {
        if (text[index] === '\\') { index += 2; continue; }
        if (text[index++] === '"') break;
      }
      return JSON.parse(text.slice(start, index));
    }
    function value(depth = 0) {
      if (depth > 128) throw new Error('JSON 嵌套超过 128 层，无法在网页中编辑。');
      whitespace();
      const char = text[index];
      if (char === '"') return string();
      if (char === '[') {
        index++; whitespace(); const result = [];
        if (text[index] === ']') { index++; return result; }
        while (true) { result.push(value(depth + 1)); whitespace(); if (text[index++] === ']') return result; }
      }
      if (char === '{') {
        index++; whitespace(); const result = Object.create(null);
        if (text[index] === '}') { index++; return result; }
        while (true) {
          whitespace(); const key = string(); whitespace(); index++;
          result[key] = value(depth + 1); whitespace(); if (text[index++] === '}') return result;
        }
      }
      for (const [literal, result] of [['true', true], ['false', false], ['null', null]]) {
        if (text.startsWith(literal, index)) { index += literal.length; return result; }
      }
      const start = index;
      while (index < text.length && /[0-9eE+\-.]/.test(text[index])) index++;
      const token = text.slice(start, index), number = Number(token);
      return /^-?(0|[1-9][0-9]*)$/.test(token) && Number.isSafeInteger(number) && token !== '-0' ? number : new NumberToken(token);
    }
    return value();
  }
  function stringify(value) {
    function write(input, depth) {
      if (input instanceof NumberToken) return input.source;
      if (input === null || typeof input !== 'object') return JSON.stringify(input);
      const indent = '  '.repeat(depth), child = `${indent}  `;
      if (Array.isArray(input)) return input.length ? `[\n${input.map(item => child + (write(item, depth + 1) ?? 'null')).join(',\n')}\n${indent}]` : '[]';
      const pairs = Object.entries(input).filter(([, item]) => item !== undefined);
      return pairs.length ? `{\n${pairs.map(([key, item]) => `${child}${JSON.stringify(key)}: ${write(item, depth + 1)}`).join(',\n')}\n${indent}}` : '{}';
    }
    return write(value, 0);
  }
  return { parse, stringify, isNumber: value => value instanceof NumberToken };
})();
