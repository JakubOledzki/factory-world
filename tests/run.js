// Runs tests/rules_spec.lua against src/shared and checks that every .luau file in src parses.
// Needs Node and the `fengari` package (Lua 5.3 in JavaScript): `npm install fengari` in this folder.
// The game code keeps to the part of Luau that plain Lua also reads, so this catches syntax errors
// and rule bugs; Roblox APIs are only tried in Studio.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const root = path.join(__dirname, "..");
const src = path.join(root, "src");

function files(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? files(path.join(dir, e.name)) : e.name.endsWith(".luau") ? [path.join(dir, e.name)] : []);
}

function newState() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  return L;
}

let failed = 0;

// Every file parses.
for (const file of files(src)) {
  const L = newState();
  const code = fs.readFileSync(file);
  if (lauxlib.luaL_loadbuffer(L, code, null, to_luastring("@" + path.relative(root, file))) !== lua.LUA_OK) {
    console.log("SYNTAX " + to_jsstring(lua.lua_tostring(L, -1)));
    failed++;
  }
}

// The rules.
const shared = {};
for (const file of files(path.join(src, "shared"))) {
  shared[path.basename(file, ".luau")] = fs.readFileSync(file, "utf8");
}
const quote = (s) => { let n = 0; while (s.includes("]" + "=".repeat(n) + "]")) n++; const eqs = "=".repeat(n); return "[" + eqs + "[\n" + s + "]" + eqs + "]"; };
const prelude = `
local SOURCES = {${Object.entries(shared).map(([k, v]) => `[${JSON.stringify(k)}] = ${quote(v)}`).join(",\n")}}
local cache = {}
local shared_folder = setmetatable({}, { __index = function(_, name) return { __shared = name } end })
local real_require = require
function load_shared(name)
  if cache[name] then return cache[name] end
  local env = setmetatable({ script = { Parent = shared_folder } }, { __index = _G })
  env.require = function(target)
    if type(target) == "table" and target.__shared then return load_shared(target.__shared) end
    return real_require(target)
  end
  local chunk = assert(load(SOURCES[name], "@src/shared/" .. name .. ".luau", "t", env))
  cache[name] = chunk()
  return cache[name]
end
math.clamp = function(x, a, b) return math.max(a, math.min(b, x)) end
local passed, failed = 0, 0
function eq(a, b, what)
  if a ~= b then error((what and (what .. ": ") or "") .. "expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok   " .. name)
  else failed = failed + 1; print("FAIL " .. name .. "\\n     " .. tostring(err)) end
end
function __summary() print(passed .. " passed, " .. failed .. " failed"); return failed end
`;
const L = newState();
const spec = fs.readFileSync(path.join(__dirname, "rules_spec.lua"), "utf8");
const program = prelude + "\n" + spec + "\nreturn __summary()";
if (lauxlib.luaL_loadbuffer(L, to_luastring(program), null, to_luastring("@tests/rules_spec.lua")) !== lua.LUA_OK
    || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
  console.log("ERROR " + to_jsstring(lua.lua_tostring(L, -1)));
  failed++;
} else {
  failed += lua.lua_tointeger(L, -1);
}
process.exit(failed ? 1 : 0);
