// Syntax-check WoW addon Lua (Lua 5.1) with luaparse.
// Usage: node tools/luacheck.js file1.lua [file2.lua ...]
// Requires luaparse (run from the repo root):
//     npm install --no-save luaparse
// A UTF-8 BOM is stripped from each file before parsing: several WoW addon
// .lua files ship with a BOM, which a strict parser otherwise rejects at 1:1.
'use strict';

const fs = require('fs');

let luaparse;
try {
	luaparse = require('luaparse');
} catch (e) {
	console.error('luaparse not found. Install it first:  npm install --no-save luaparse');
	process.exit(2);
}

const files = process.argv.slice(2);
if (files.length === 0) {
	console.error('usage: node tools/luacheck.js <file.lua> [...]');
	process.exit(2);
}

let failed = 0;
for (const f of files) {
	let src = fs.readFileSync(f, 'utf8');
	if (src.charCodeAt(0) === 0xfeff) src = src.slice(1);
	try {
		luaparse.parse(src, { luaVersion: '5.1' });
		console.log('OK   ' + f);
	} catch (e) {
		failed = 1;
		console.log('FAIL ' + f + ' :: ' + e.message + (e.line ? ' (line ' + e.line + ')' : ''));
	}
}
process.exit(failed);
