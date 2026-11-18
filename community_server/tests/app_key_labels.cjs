const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// Exercise the production pure display function without a DOM or a test-only
// global API. This never changes the canonical keys used in downloaded JSON.
const source = fs.readFileSync(path.join(__dirname,'../src/web/apps.js'),'utf8');
const declaration = source.match(/  function displayKeys\([\s\S]*?\n  }/);
assert.ok(declaration,'Production display formatter exists');
const display = vm.runInNewContext(`(${declaration[0]})`);
const mac = {family:'macos',supportedOS:['macos']};
const shared = {family:'windowsLinux',supportedOS:['windows','linux']};
assert.equal(display(['META','ALT','SHIFT','CTRL','A'],mac),'Command + Option + Shift + Ctrl + A');
assert.equal(display(['META','ALT','A'],shared,'windows'),'Windows + Alt + A');
assert.equal(display(['META','A'],shared,'linux'),'Super + A');
assert.equal(display(['META','A'],shared),'Windows / Super + A');
assert.equal(display(['META','A'],{family:'windowsLinux',supportedOS:['windows']}),'Windows + A');
assert.equal(display(['META','A'],{family:'windowsLinux',supportedOS:['linux']}),'Super + A');
assert.equal(display(['LEFT_BRACKET','RIGHT_BRACKET','SLASH','BACKSLASH','QUOTE','BACKTICK','COMMA','PERIOD','SEMICOLON','MINUS','EQUAL'],mac),"[ + ] + / + \\ + ' + ` + , + . + ; + - + =");
assert.equal(display(['PAGE_UP','PAGE_DOWN','ENTER','BACKSPACE','SPACE'],shared),'Page Up + Page Down + Enter + Backspace + Space');
assert.equal(display(['LEFT','RIGHT','UP','DOWN','F12'],mac),'← + → + ↑ + ↓ + F12');
assert.equal(display([],mac),'');
const raw = ['META','LEFT_BRACKET']; display(raw,mac); assert.deepEqual(raw,['META','LEFT_BRACKET']);
console.log(JSON.stringify({passed:true,checks:11,rawDownloadKeysUnchanged:true}));
