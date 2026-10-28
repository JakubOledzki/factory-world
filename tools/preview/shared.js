// Runs the game's pure modules (src/shared) in Node through fengari, so the preview draws the very
// models the server builds. `call("Models.Tree(5)")` evaluates a Lua expression and returns it as JSON.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const sharedDir = path.join(__dirname, "../../src/shared");

function quote(s) {
  let n = 0;
  while (s.includes("]" + "=".repeat(n) + "]")) n++;
  const eqs = "=".repeat(n);
  return "[" + eqs + "[\n" + s + "]" + eqs + "]";
}

function luaShared() {
  const sources = fs.readdirSync(sharedDir).filter((f) => f.endsWith(".luau"))
    .map((f) => `[${JSON.stringify(path.basename(f, ".luau"))}] = ${quote(fs.readFileSync(path.join(sharedDir, f), "utf8"))}`);
  const prelude = `
local SOURCES = {${sources.join(",\n")}}
local cache = {}
local folder = setmetatable({}, { __index = function(_, name) return { __shared = name } end })
function load_shared(name)
  if cache[name] then return cache[name] end
  local env = setmetatable({ script = { Parent = folder } }, { __index = _G })
  env.require = function(t) return load_shared(t.__shared) end
  cache[name] = assert(load(SOURCES[name], "@src/shared/" .. name .. ".luau", "t", env))()
  return cache[name]
end
for _, n in ipairs({ "Models", "PlotLayout", "Items", "Smelting" }) do _G[n] = load_shared(n) end
local function encode(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then
      local out = {}
      for i = 1, #v do out[i] = encode(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = string.format("%q", tostring(k)) .. ":" .. encode(x) end
    return "{" .. table.concat(out, ",") .. "}"
  elseif t == "string" then return string.format("%q", v)
  elseif t == "number" then return string.format("%.6g", v)
  elseif t == "boolean" then return tostring(v)
  end
  return "null"
end
json = encode
`;
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  if (lauxlib.luaL_dostring(L, to_luastring(prelude)) !== lua.LUA_OK) throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
  return {
    call(expr) {
      if (lauxlib.luaL_dostring(L, to_luastring("return json(" + expr + ")")) !== lua.LUA_OK) {
        throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
      }
      const text = to_jsstring(lua.lua_tostring(L, -1));
      lua.lua_pop(L, 1);
      return JSON.parse(text);
    },
  };
}

module.exports = { luaShared };
