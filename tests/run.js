const fs = require('fs'), path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
const root = process.argv[2], scenario = fs.readFileSync(process.argv[3], 'utf8');
const BS = String.fromCharCode(92);
const ADDON = path.basename(path.resolve(root));
const toc = fs.readFileSync(path.join(root, ADDON + '.toc'), 'utf8')
  .split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith('#'));
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
function run(src, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(name)) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
    console.log('ERROR in', name, ':', to_jsstring(lua.lua_tostring(L, -1))); process.exit(1);
  }
}
run('io_write = print', 'init');
run(fs.readFileSync(path.join(__dirname, 'stub.lua'), 'utf8'), 'stub');
for (const extra of process.argv.slice(4)) run(fs.readFileSync(path.join(__dirname, extra), 'utf8'), extra);
run('NS = {}', 'ns');
for (const f of toc) {
  const rel = f.split(BS).join('/');
  const src = fs.readFileSync(path.join(root, rel), 'utf8');
  run(`local chunk = assert(load(${JSON.stringify(src)}, "@${rel}")); chunk("${ADDON}", NS)`, rel);
}
console.log('all files loaded');
run(scenario, 'scenario');
run('if FAILED then error(FAILED .. " test(s) failed") end', 'result');
