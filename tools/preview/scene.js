// Builds the preview scenes from the game's own models and layout (src/shared) the way the server
// puts them together (Services/World.luau, Services/Plots.luau), and takes the screenshots in
// docs/screenshots. Needs fengari, three and Playwright: `npm install`, then
// `node tools/preview/scene.js` (Playwright's Chromium must be installed).
const fs = require("fs");
const path = require("path");
const { luaShared } = require("./shared.js");

const lua = luaShared();
const L = lua.call("{ Count = PlotLayout.Count, Size = PlotLayout.Size, Ring = PlotLayout.Ring, Mines = PlotLayout.Mines,"
  + " WildTrees = PlotLayout.WildTrees, FurnaceSlotTiles = PlotLayout.FurnaceSlotTiles, Stall = PlotLayout.Stall, Workbench = PlotLayout.Workbench,"
  + " Fountain = PlotLayout.Fountain, SquareSpawn = PlotLayout.SquareSpawn, Spawn = PlotLayout.Spawn }");
const center = (i) => lua.call(`{ PlotLayout.Center(${i}) }`);

const cyl = (len, d, pos, color, material) => ({ shape: "Cylinder", size: [len, d, d], pos, rot: [0, 0, Math.PI / 2], color, material });
const block = (size, pos, color, material, yaw = 0) => ({ shape: "Block", size, pos, rot: [0, yaw, 0], color, material });

// The top of the square's paving (World.luau): what stands on the square stands on it.
const PAVING = 0.4;

function square() {
  const objects = [];
  const big = 2 * lua.call("PlotLayout.GroundHalf()");
  objects.push({ at: [0, 0, 0], parts: [
    block([big, 2, big], [0, -1.5, 0], [92, 136, 66], "Grass"),
    cyl(2, 64, [0, PAVING - 1, 0], [168, 160, 148], "Cobblestone"),
    cyl(2, 22, [0, PAVING - 0.95, 0], [190, 184, 172], "Pavement"),
    cyl(0.4, 7, [L.SquareSpawn.x, PAVING + 0.1, L.SquareSpawn.z], [200, 186, 150], "Marble"),
  ] });
  objects.push({ at: [L.Fountain.x, PAVING, L.Fountain.z], parts: lua.call("Models.Fountain()") });
  objects.push({ at: [L.Stall.x, PAVING, L.Stall.z], yaw: L.Stall.yaw, parts: lua.call("Models.Stall()") });
  // The merchant stands 2.6 studs behind the counter (CFrame.new(0, 0, 2.6) in the stall's frame).
  const s = Math.sin(L.Stall.yaw), c = Math.cos(L.Stall.yaw);
  objects.push({ at: [L.Stall.x + 2.6 * s, PAVING, L.Stall.z + 2.6 * c], yaw: L.Stall.yaw, parts: lua.call("Models.Merchant()") });
  objects.push({ at: [L.Workbench.x, PAVING, L.Workbench.z], yaw: L.Workbench.yaw, parts: lua.call("Models.Workbench()") });
  for (let i = 1; i <= L.Count; i++) {
    const [x, z] = center(i);
    const length = L.Ring - L.Size / 2 - 30;
    const d = Math.hypot(x, z), dx = x / d, dz = z / d;
    const mid = [dx * (31 + length / 2), 0, dz * (31 + length / 2)];
    const yaw = Math.atan2(dx, dz);
    objects.push({ at: mid, yaw, parts: [
      block([7.4, 0.2, length + 2], [0, -0.48, 0], [112, 96, 70], "Ground"),
      block([6, 0.2, length + 2], [0, -0.42, 0], [156, 134, 100], "Ground"),
    ] });
  }
  return objects;
}

// The forest between the plots (World.PlantForest); `near` = [x, z, radius] keeps only the trees
// around that point, to spare the browser.
function forest(near) {
  const trees = lua.call("PlotLayout.ForestTrees()");
  return trees.filter((t) => !near || Math.hypot(t.x - near[0], t.z - near[1]) < near[2])
    .map((t) => ({ at: [t.x, 0, t.z], yaw: t.yaw, parts: lua.call(`Models.ForestTree(${t.seed})`) }));
}

// One plot as the server puts it together (Plots.buildPlot, Grid): `opts` says which wild trees
// were cut (and saplings planted instead) and which furnaces stand at the first tiles the game
// gives furnaces from the old slots (and whether they are lit).
function plot(index, opts = {}) {
  const [cx, cz] = center(index);
  const objects = [];
  if (!opts.biome) objects.push({ at: [cx, 0, cz], parts: [block([L.Size, 1, L.Size], [0, -0.45, 0], [116, 158, 78], "Grass")] });
  // A bought plot shown on the player's place (Plots.buildPlot) has its biome's ground.
  const biome = opts.biome ? `Lands.Biomes.${opts.biome}` : "nil";
  objects.push({ at: [cx, 0, cz], parts: lua.call(`Models.PlotDecor(${index * 100}, PlotLayout.Size, PlotLayout.OpenSides(${index}), PlotLayout.FenceGaps(), ${biome})`) });
  objects.push({ at: [cx, 0, cz], parts: lua.call(`Models.Railway(PlotLayout.Rail, PlotLayout.StationSpan())`) });
  {
    const s = lua.call("PlotLayout.Station");
    const [x, z] = lua.call(`{ PlotLayout.TileCenter(${s.x}, ${s.z}, ${s.size}) }`);
    objects.push({ at: [cx + x, 0, cz + z], yaw: -Math.PI / 2, parts: lua.call("Models.Station()") });
  }
  const half = L.Size / 2, d = Math.hypot(cx, cz), tx = -cx / d, tz = -cz / d;
  const sign = [cx + tx * (half - 5) + tz * 6, 0, cz + tz * (half - 5) - tx * 6];
  // CFrame.lookAt(at, at + toSquare): the front (-z) faces the square.
  objects.push({ at: sign, yaw: Math.atan2(-tx, -tz), parts: lua.call(`Models.Signpost(${index})`) });
  L.Mines.forEach((m, k) => objects.push({ at: [cx + m.x, 0, cz + m.z], yaw: Math.PI, parts: lua.call(`Models.Mine(${index * 10 + k + 1})`) }));
  const wild = opts.biome ? lua.call(`Lands.WildTrees("${opts.biome}")`) : L.WildTrees;
  const snow = opts.biome ? !!lua.call(`Lands.Biomes.${opts.biome}.snow`) : false;
  wild.forEach((t, k) => {
    const id = index * 20 + k + 1;
    const [x, z] = lua.call(`{ PlotLayout.TileCenter(${t.x}, ${t.z}, 1) }`);
    // As Grid.show: the tile's yaw (pi for rotation 0) and a turn of its own.
    const yaw = Math.PI + (id % 7) * 0.9;
    const sapling = (opts.cut || []).includes(k);
    objects.push({ at: [cx + x, 0, cz + z], yaw, parts: lua.call(sapling ? `Models.Sapling(${id})` : `Models.Tree(${id}, ${snow})`) });
  });
  L.FurnaceSlotTiles.forEach((t, k) => {
    const f = (opts.furnaces || [])[k];
    const [x, z] = lua.call(`{ PlotLayout.TileCenter(${t.x}, ${t.z}, 2) }`);
    if (f) objects.push({ at: [cx + x, 0, cz + z], yaw: Math.PI, parts: lua.call("Models.Furnace(true)"), lit: f === "lit" });
  });
  return { objects, cx, cz, sign };
}

const caption = "Podgląd Factory World 3D: modele wprost z kodu gry (src/shared/Models.luau). W Robloxie oświetlenie, materiały i postacie wyglądają nieco inaczej.";

// A tile as the game draws one (client/Ui/ItemGrid.luau, ItemGrid.Slot): the item's picture
// (drawn by index.html from Shared.Icons), `text` in the corner and an optional caption under it.
function slot(id, text = "", o = {}) {
  const size = o.size || 54;
  const border = o.stroke ? `border:${o.strokeWidth || 2.5}px solid ${o.stroke};` : "";
  const tile = `<div class="slot" style="width:${size}px;height:${size}px;${border}">`
    + (id ? `<i class="ic" data-icon="${id}"${o.dim ? ' style="opacity:.45"' : ""}></i>` : "")
    + (o.badge ? `<span class="badge">${o.badge}</span>` : "") + (o.bar != null ? `<i style="position:absolute;left:3px;bottom:2px;height:3px;width:${o.bar * (size - 8)}px;background:#ff8c32"></i>` : "")
    + (text ? `<b>${text}</b>` : "") + `</div>`;
  if (o.caption == null) return tile;
  return `<div style="width:${size}px;flex:none">${tile}<div class="scap" style="color:${o.captionColor || "#a0a6b2"}">${o.caption}</div></div>`;
}

// The inventory grid: `entries` are [id, quantity], padded to `count` tiles.
function itemGrid(entries, columns, count) {
  const tiles = [];
  for (let i = 0; i < count; i++) tiles.push(entries[i] ? slot(entries[i][0], entries[i][1]) : slot(null));
  return `<div style="display:grid;grid-template-columns:repeat(${columns},54px);gap:4px;margin:4px 0">${tiles.join("")}</div>`;
}

// What a player in the screenshots has, for the counts in the windows.
const have = { tool_pickaxe: 1, tool_axe: 1, coal: 31, copper_ore: 8, iron_ingot: 12, stone: 126, wood: 22, sapling: 3,
  logistics_belt: 6, logistics_inserter: 2, storage_wooden_chest: 1, tin_ore: 4, nails: 15, iron_ore: 14, copper_ingot: 4, planks: 12 };
const haveGrid = (columns, count) => itemGrid(Object.entries(have), columns, count);
const name = (id) => lua.call(`Items.Name("${id}")`);
const GOLD = "#ffd65a", GREEN = "#8cd77d", RED = "#f0695f";
const ready = (r) => r.ingredients.every(([id, n]) => (have[id] || 0) >= n);

// Ingredient tiles with have/need under each, red when short (client/Ui/Recipes.luau).
const ingredients = (list, size = 40) => `<div style="display:flex;gap:14px">${list.map(([id, n]) =>
  slot(id, n, { size, caption: `${have[id] || 0}/${n}`, captionColor: (have[id] || 0) >= n ? GREEN : RED })).join("")}</div>`;

// The recipe grid and the card of the chosen recipe (Recipes.Picker, Recipes.Card).
function picker(recipes, selected, marked) {
  return `<div style="display:flex;flex-wrap:wrap;gap:6px">${recipes.map((r) => slot(r.id, r.quantity > 1 ? "×" + r.quantity : "", {
    size: 56, dim: r.locked, badge: r.locked ? "🔒" : r.id === marked ? "▶" : null,
    stroke: r.id === selected ? GOLD : !r.locked && ready(r) ? GREEN : null, strokeWidth: r.id === selected ? 2.5 : 1.5 })).join("")}</div>`;
}
function card(r, subtitle, actions) {
  return `<div class="card" style="height:156px"><div style="position:absolute;left:10px;top:10px">${slot(r.id, r.quantity > 1 ? "×" + r.quantity : "", { size: 88 })}</div>
    <div style="position:absolute;left:110px;top:8px;font-weight:800;font-size:18px">${name(r.id)}${r.quantity > 1 ? " × " + r.quantity : ""}</div>
    <div class="muted" style="position:absolute;left:110px;top:32px;font-size:13px">Czas: ${r.time} s${subtitle ? "&nbsp;&nbsp; " + subtitle : ""}</div>
    <div style="position:absolute;left:110px;top:52px">${ingredients(r.ingredients)}</div>
    <div style="position:absolute;left:110px;top:116px;display:flex;gap:8px;align-items:center;font-size:13px">${actions}</div></div>`;
}
const tabs = (list, current) => `<div class="tabs">${list.map((t) => `<span class="btn ${t === current ? "alt" : "off"}">${t}</span>`).join("")}</div>`;
const catTabs = (current, ids) => { const cs = lua.call("Items.Categories"); const present = new Set(ids.map((id) => lua.call(`Items.Category("${id}")`)));
  return `<div style="display:flex;flex-wrap:wrap;gap:6px">${[{ id: "all", name: "Wszystko" }, ...cs.filter((c) => present.has(c.id))].map((c) =>
    `<span class="btn" style="width:98px;box-sizing:border-box;text-align:center;padding:6px 0;background:${c.id === current ? "#6e5c28" : "#2c313b"}">${c.name}</span>`).join("")}</div>`; };
// What is in a machine or furnace: tiles, an arrow with the progress, what is ready (Machine.Contents).
const contents = (inputs, progress, output) => `<div style="display:flex;gap:8px;align-items:flex-start">${inputs.join("")}
  <div style="width:90px;flex:none;text-align:center"><div class="muted" style="font-size:26px;line-height:34px">➜</div><div class="bar" style="height:10px;margin:4px 4px 0;background:#181b21"><i style="width:${progress * 100}%"></i></div></div>${output}</div>`;

function views() {
  const out = {};
  // 1. The square and all plots from above.
  {
    let objects = square().concat(forest());
    for (let i = 1; i <= L.Count; i++) objects = objects.concat(plot(i, { furnaces: ["lit", i % 2 ? "lit" : "cold", i % 3 ? "cold" : null], cut: i % 2 ? [1, 4] : [] }).objects);
    out["1-plac-i-dzialki"] = { objects, camera: { pos: [330, 560, 820], look: [0, 0, 60], fov: 60 }, shadowRadius: 700, fog: [1100, 2400], hud: "1 284,50 $", caption,
      labels: [{ at: [L.Stall.x, 14, L.Stall.z], text: "Handlarz", color: "#ffe678", size: 15 }] };
  }
  // 2. Mining on the player's plot.
  {
    const p = plot(1, { furnaces: ["lit", "lit", "cold"], cut: [0, 5] });
    const { cx, cz } = p;
    const objects = square().concat(p.objects, forest([cx, cz - 100, 220]));
    out["2-kopanie-na-dzialce"] = { objects, camera: { pos: [cx + 11, 13, cz - 72], look: [cx - 1, 3, cz - 96] }, shadowRadius: 70, hud: "1 284,50 $", caption,
      avatars: [{ at: [cx + 0.5, 0, cz - 85.5], yaw: Math.PI, shirt: [200, 60, 60], pose: -1.9 }],
      labels: [{ at: [cx + 0, 13, cz - 102], text: "Kopalnia (poziom 1) 37/50" }],
      prompts: [{ at: [cx + 5, 8, cz - 89], action: "Kop", object: "Kopalnia", progress: 0.62 }],
      overlay: `<div class="toast">+1 Kamień, +1 Ruda żelaza</div>` };
  }
  // 3. Furnaces with the furnace window.
  {
    const p = plot(1, { furnaces: ["lit", "lit", "cold", "lit"], cut: [5] });
    const objects = square().concat(p.objects);
    const { cx, cz } = p;
    out["3-piec"] = { objects, camera: { pos: [cx + 6, 9, cz - 39], look: [cx + 17, 3, cz - 56] }, shadowRadius: 50, hud: "1 284,50 $", caption,
      avatars: [{ at: [cx + 13, 0, cz - 48], yaw: Math.PI + 0.3, shirt: [200, 60, 60] }],
      overlay: `<div class="win" style="width:460px;right:16px;bottom:24px"><div class="hd">Piec kamienny<span class="x">✕</span></div><div class="bd">
        <div class="muted" style="font-size:14px">W piecu (kliknij kafelek, aby wyjąć):</div>
        ${contents([slot("iron_ore", "23/50", { size: 56, caption: "Ruda" }), slot("coal", "4/50", { size: 56, caption: "Węgiel (żar 3)" })], 0.64,
          slot("iron_ingot", "12", { size: 56, caption: "Gotowe", captionColor: "#ebecf0" }))}
        <div class="muted" style="font-size:14px">Ekwipunek: kliknij rudę albo węgiel, aby włożyć (Shift: połowę)</div>
        ${haveGrid(7, 21)}
        <div style="display:flex;gap:8px;margin-top:4px"><span class="btn red">Schowaj piec</span></div>
      </div></div>` };
  }
  // 4. The merchant's square.
  {
    let objects = square().concat(forest([0, 0, 160]));
    for (let i = 1; i <= L.Count; i++) objects = objects.concat(plot(i, { furnaces: ["lit"] }).objects);
    const buys = lua.call("Prices.Buys");
    const boom = { iron_ore: 55, iron_ingot: 60, nails: 40 };
    const sellable = lua.call("Items.Order").filter((id) => have[id] && buys[id]).map((id) => [id, buys[id]]);
    out["4-handlarz"] = { objects, camera: { pos: [17, 6.5, 1], look: [2, 4.5, -17] }, shadowRadius: 60, hud: "1 284,50 $", caption,
      avatars: [{ at: [4, 0, -10], yaw: Math.PI + 0.4, shirt: [200, 60, 60] }],
      labels: [{ at: [L.Stall.x, 13.5, L.Stall.z], text: "Handlarz", color: "#ffe678", size: 20 }, { at: [L.Workbench.x, 7.5, L.Workbench.z], text: "Stół warsztatowy", color: "#dce6ff", size: 15 }],
      overlay: `<div class="win" style="width:580px;right:16px;bottom:16px"><div class="hd">Handlarz<span class="x">✕</span></div><div class="bd">
        <div class="card" style="background:#5c481e;padding:7px 10px;font-size:13px;line-height:1.35"><b>Boom na stal</b> (jeszcze 3 h 12 min): Huty nie nadążają z zamówieniami. Ruda żelaza, sztabki, stal i gwoździe są w cenie.</div>
        ${tabs(["Sprzedaj", "Kup"], "Sprzedaj")}
        ${catTabs("ores", sellable.map(([id]) => id))}
        <div class="card" style="height:112px"><div style="position:absolute;left:10px;top:12px">${slot("iron_ore", "14", { size: 88 })}</div>
          <div style="position:absolute;left:110px;top:10px;font-weight:800;font-size:18px">Ruda żelaza</div>
          <div class="gold" style="position:absolute;left:110px;top:36px;font-size:15px">Płaci: 9,30 $ za sztukę &nbsp;(+55%, zwykle 6 $) &nbsp;·&nbsp; masz 14</div>
          <div style="position:absolute;left:110px;top:66px;display:flex;gap:8px"><span class="btn" style="width:100px;text-align:center">Sprzedaj 1</span><span class="btn" style="width:100px;text-align:center">Sprzedaj 10</span><span class="btn alt" style="width:100px;text-align:center">Wszystko</span></div></div>
        <div style="display:flex;flex-wrap:wrap;gap:4px 8px">${sellable.filter(([id]) => lua.call(`Items.Category("${id}")`) === "ores").map(([id, cents]) => slot(id, have[id], { size: 56, caption: lua.call(`Money.Format(${boom[id] ? Math.round(cents * (100 + boom[id]) / 100) : cents})`), captionColor: boom[id] ? GREEN : GOLD, stroke: id === "iron_ore" ? GOLD : null })).join("")}</div>
      </div></div>` };
  }
  // 5. The models side by side.
  {
    const objects = [{ at: [0, 0, 0], parts: [block([120, 1, 60], [0, -0.5, 0], [116, 158, 78], "Grass"), block([90, 0.2, 18], [0, 0.02, 0], [168, 160, 148], "Cobblestone")] }];
    const row = [
      ["Kopalnia", "Models.Mine(13)", -30, Math.PI + 0.5],
      ["Sosny", "Models.Tree(21)", -12, 0], [null, "Models.Tree(24)", -7, 2],
      ["Piec kamienny", "Models.Furnace()", 3, Math.PI - 0.5],
      ["Stół warsztatowy", "Models.Workbench()", 15, Math.PI + 0.2],
      ["Stragan handlarza", "Models.Stall()", 32, Math.PI - 0.35],
    ];
    const labels = [];
    for (const [name, expr, x, yaw] of row) {
      objects.push({ at: [x, 0, 0], yaw, parts: lua.call(expr), lit: true });
      if (name) labels.push({ at: [x === -12 ? -9.5 : x, 0, 9], text: name, cls: "tag" });
    }
    const s = Math.sin(Math.PI - 0.35), c = Math.cos(Math.PI - 0.35);
    objects.push({ at: [32 + 2.6 * s, 0, 2.6 * c], yaw: Math.PI - 0.35, parts: lua.call("Models.Merchant()") });
    objects.push({ at: [46, 0, 0], parts: lua.call("Models.Fountain()") });
    labels.push({ at: [46, 0, 9], text: "Fontanna", cls: "tag" });
    out["5-modele"] = { objects, camera: { pos: [8, 22, 52], look: [8, 3, 0], fov: 55 }, shadowRadius: 70, caption, labels };
  }
  // 17. The machines side by side, close up.
  {
    const objects = [{ at: [0, 0, 0], parts: [block([140, 1, 60], [0, -0.5, 0], [116, 158, 78], "Grass")] }];
    const row = [
      ["Tartak", "Models.Machine('furniture_sawmill')", -29],
      ["Kamieniarz", "Models.Machine('furniture_stonemason')", -19.5],
      ["Kruszarka", "Models.Machine('furniture_crusher')", -10],
      ["Odlewnia", "Models.Machine('furniture_foundry')", 2.5],
      ["Generator", "Models.Generator()", 15],
      ["Skrzynia", "Models.WoodenChest()", 23],
      ["Podajnik", "Models.Inserter()", 28.5],
    ];
    const labels = [];
    for (const [name, expr, x] of row) {
      objects.push({ at: [x, 0, 0], yaw: Math.PI - 0.35, parts: lua.call(expr), lit: true });
      labels.push({ at: [x, 0, 5.5], text: name, cls: "tag" });
    }
    out["17-maszyny"] = { objects, camera: { pos: [-1, 15, 33], look: [-1, 3, 0], fov: 60 }, shadowRadius: 70, caption, labels };
  }
  // 18. The station, a train, a chest and an inserter, close up.
  {
    const objects = [{ at: [0, 0, 0], parts: [block([120, 1, 80], [0, -0.5, 0], [116, 158, 78], "Grass")] }];
    const cargo = lua.call("{ Items.Colors[Items.IronIngot], Items.Colors[Items.Planks] }");
    objects.push({ at: [-10, 0, -10], yaw: Math.PI - 0.3, parts: lua.call("Models.Station()"), lit: true });
    objects.push({ at: [20, 0, 8], yaw: -Math.PI / 2 + 0.15, parts: lua.call(`Models.Train(2, { ${cargo.map((c) => `{ ${c.join(",")} }`).join(",")} })`), lit: true });
    objects.push({ at: [8, 0, -6], yaw: Math.PI - 0.4, parts: lua.call("Models.WoodenChest()"), lit: true });
    objects.push({ at: [14, 0, -6], yaw: Math.PI - 0.4, parts: lua.call("Models.Inserter()"), lit: true });
    out["18-kolej-z-bliska"] = { objects, camera: { pos: [4, 15, 38], look: [4, 3, 0], fov: 60 }, shadowRadius: 60, caption };
  }
  // 6. A little factory on the build grid, worked out by the game's own rules (Logistics.Run).
  {
    const p = plot(1, { furnaces: ["lit", "cold"], cut: [5] });
    const objects = square().concat(p.objects);
    const { cx, cz } = p;
    const state = lua.call(`(function()
      local o, n = {}, 0
      local function add(kind, x, z, rot) n = n + 1; local obj = Logistics.New(n, kind, x + 22, z + 7, rot); table.insert(o, obj); return obj end
      local a = add(Items.WoodenChest, 1, 1, 1)
      Logistics.Store(a.items, Items.IronOre, 40); Logistics.Store(a.items, Items.Coal, 10)
      add(Items.Inserter, 2, 1, 1)
      for x = 3, 7 do add(Items.Belt, x, 1, 1) end
      add(Items.Inserter, 8, 1, 1)
      add(Items.Inserter, 11, 1, 1)
      add(Items.WoodenChest, 12, 1, 1)
      local c = add(Items.WoodenChest, 1, 3, 1)
      Logistics.Store(c.items, Items.CopperOre, 60)
      add(Items.Inserter, 2, 3, 1)
      for x = 3, 5 do add(Items.Belt, x, 3, 1) end
      add(Items.Belt, 6, 3, 0)
      for x = 6, 8 do add(Items.Belt, x, 4, 1) end
      add(Items.Inserter, 9, 4, 1)
      add(Items.WoodenChest, 10, 4, 1)
      local furnace = { id = 99, tile = { x = 31, z = 8 }, rot = 0, state = Smelting.Empty() }
      local bends = Logistics.Bends(o)
      Logistics.Run(o, { furnace }, 0, 41.4)
      for _, obj in ipairs(o) do obj.bend = bends[obj.id] end
      return { objects = o, lit = Smelting.Advance(furnace.state, 41.4).startedAt ~= nil, furnace = furnace.tile }
    end)()`);
    const yaws = [Math.PI, -Math.PI / 2, 0, Math.PI / 2];
    const tileAt = (x, z, size) => lua.call(`{ PlotLayout.TileCenter(${x}, ${z}, ${size}) }`);
    const models = { logistics_belt: lua.call("Models.Belt()"), logistics_inserter: lua.call("Models.Inserter()"), storage_wooden_chest: lua.call("Models.WoodenChest()") };
    const colors = lua.call("Items.Colors");
    for (const o of state.objects) {
      const [ox, oz] = tileAt(o.x, o.z, 1);
      const at = [cx + ox, 0, cz + oz], yaw = yaws[o.rot];
      if (o.kind === "logistics_inserter") {
        const angle = Math.PI * (1 - o.swing / 4);
        objects.push({ at, yaw, parts: models[o.kind].filter((q) => q.group !== "arm") });
        const arm = models[o.kind].filter((q) => q.group === "arm").map((q) => q.name === "Hand" && o.hand ? { ...q, hidden: false, color: colors[o.hand] } : q);
        objects.push({ at, yaw: yaw + angle, parts: arm });
      } else if (o.kind === "logistics_belt") {
        objects.push({ at, yaw, parts: lua.call(`Models.Belt(${o.bend})`) });
      } else {
        objects.push({ at, yaw, parts: models[o.kind] });
      }
      if (o.belt) {
        const items = [];
        o.belt.forEach((item, i) => {
          if (!item) return;
          const pos = lua.call(`Models.BeltSlot(${i + 1}, Logistics.BeltSlots, ${o.bend})`);
          items.push({ shape: "Ball", size: [0.75, 0.75, 0.75], pos, rot: [0, 0, 0], color: colors[item], material: "SmoothPlastic" });
        });
        objects.push({ at, yaw, parts: items });
      }
    }
    const [fx, fz] = tileAt(state.furnace.x, state.furnace.z, 2);
    objects.push({ at: [cx + fx, 0, cz + fz], yaw: Math.PI, parts: lua.call("Models.Furnace(true)"), lit: state.lit });
    // The see-through ghost of the next belt under the pointer.
    const [gx, gz] = tileAt(36, 9, 1);
    const ghost = models.logistics_inserter.map((q) => ({ ...q, transparency: 0.3 })).concat(lua.call("Models.BuildMarker(Items.Inserter, PlotLayout.Grid.tile)"));
    objects.push({ at: [cx + gx, 0, cz + gz], yaw: yaws[1], parts: ghost });
    // The grid's lines, which the player sees while building (BuildBar.showLines).
    const G = lua.call("PlotLayout.Grid"), lines = [];
    const w = G.width * G.tile, d = G.depth * G.tile;
    for (let i = 0; i <= G.width; i++) lines.push({ shape: "Block", size: [0.12, 0.05, d], pos: [G.x + i * G.tile, 0.08, G.z + d / 2], rot: [0, 0, 0], color: [255, 255, 255], material: "SmoothPlastic", transparency: 0.55 });
    for (let i = 0; i <= G.depth; i++) lines.push({ shape: "Block", size: [w, 0.05, 0.12], pos: [G.x + w / 2, 0.08, G.z + i * G.tile], rot: [0, 0, 0], color: [255, 255, 255], material: "SmoothPlastic", transparency: 0.55 });
    objects.push({ at: [cx, 0, cz], parts: lines });
    const btn = (t, on) => `<span class="btn${on ? "" : " alt"}" style="width:128px;text-align:center;white-space:nowrap;font-size:12px">${t}</span>`;
    out["6-budowanie"] = { objects, camera: { pos: [cx + 6, 34, cz - 46], look: [cx + 4, 0, cz - 72], fov: 55 }, shadowRadius: 60, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="left:50%;transform:translateX(-50%);bottom:16px;width:960px"><div class="bd" style="padding-top:10px">
        <div style="display:flex;gap:6px">${btn("Taśmociąg (6)")}${btn("Podajnik (2)", true)}${btn("Drewniana skrzynia (1)")}${btn("Piec kamienny (0)")}${btn("Sadzonka (3)")}<span class="btn red">Rozbiórka [X]</span><span class="btn alt">Obróć [R]</span></div>
        <div class="muted" style="margin-top:8px">Kliknij, by postawić. Przeciągnij, by ułożyć taśmę (skręca razem z ruchem). 1–5 wybór, R obrót, X rozbiórka, B koniec.</div>
      </div></div>` };
  }
  // 7. Processing machines on the grid, fed by inserters, and the research window.
  {
    const p = plot(1, { cut: [5] });
    const objects = square().concat(p.objects);
    const { cx, cz } = p;
    const state = lua.call(`(function()
      local o, n = {}, 0
      local function add(kind, x, z, rot) n = n + 1; local obj = Logistics.New(n, kind, x + 20, z + 10, rot); table.insert(o, obj); return obj end
      local wood = add(Items.WoodenChest, 0, 1, 1); Logistics.Store(wood.items, Items.Wood, 40)
      add(Items.Inserter, 1, 1, 1)
      local mill = add(Items.Sawmill, 2, 0, 1); mill.machine = Processing.SetRecipe(Items.Sawmill, mill.machine, Items.Planks, 0)
      add(Items.Inserter, 4, 1, 1)
      for x = 5, 7 do add(Items.Belt, x, 1, 1) end
      add(Items.Inserter, 8, 1, 1)
      add(Items.WoodenChest, 9, 1, 1)
      local stone = add(Items.WoodenChest, 0, 5, 1); Logistics.Store(stone.items, Items.Stone, 40)
      add(Items.Inserter, 1, 5, 1)
      local crusher = add(Items.Crusher, 2, 4, 1); crusher.machine = Processing.SetRecipe(Items.Crusher, crusher.machine, Items.Sand, 0)
      add(Items.Inserter, 4, 5, 1)
      add(Items.WoodenChest, 5, 5, 1)
      local mason = add(Items.Stonemason, 12, 0, 0); mason.machine = Processing.SetRecipe(Items.Stonemason, mason.machine, Items.StoneBlocks, 0)
      mason.machine = Processing.Load(Items.Stonemason, mason.machine, Items.Stone, 30, 0)
      local foundry = add(Items.Foundry, 11, 4, 0); foundry.machine = Processing.SetRecipe(Items.Foundry, foundry.machine, Items.Bricks, 0)
      foundry.machine = Processing.Load(Items.Foundry, foundry.machine, Items.Sand, 20, 0)
      foundry.machine = Processing.Load(Items.Foundry, foundry.machine, Items.Stone, 20, 0)
      foundry.machine = Processing.Load(Items.Foundry, foundry.machine, Items.Coal, 5, 0)
      local bends = Logistics.Bends(o)
      Logistics.Run(o, {}, 0, 23.4)
      for _, obj in ipairs(o) do
        obj.bend = bends[obj.id]
        if obj.machine then obj.working = Processing.Advance(obj.kind, obj.machine, 23.4).startedAt ~= nil end
      end
      return o
    end)()`);
    const yaws = [Math.PI, -Math.PI / 2, 0, Math.PI / 2];
    const tileAt = (x, z, size) => lua.call(`{ PlotLayout.TileCenter(${x}, ${z}, ${size}) }`);
    const colors = lua.call("Items.Colors");
    const sizes = lua.call("Logistics.Sizes");
    for (const o of state) {
      const [ox, oz] = tileAt(o.x, o.z, sizes[o.kind] || 1);
      const at = [cx + ox, 0, cz + oz], yaw = yaws[o.rot];
      if (o.kind === "logistics_inserter") {
        const parts = lua.call("Models.Inserter()");
        objects.push({ at, yaw, parts: parts.filter((q) => q.group !== "arm") });
        const arm = parts.filter((q) => q.group === "arm").map((q) => q.name === "Hand" && o.hand ? { ...q, hidden: false, color: colors[o.hand] } : q);
        objects.push({ at, yaw: yaw + Math.PI * (1 - o.swing / 4), parts: arm });
      } else if (o.kind === "logistics_belt") {
        objects.push({ at, yaw, parts: lua.call(`Models.Belt(${o.bend})`) });
        const items = [];
        o.belt.forEach((item, i) => {
          if (!item) return;
          items.push({ shape: "Ball", size: [0.75, 0.75, 0.75], pos: lua.call(`Models.BeltSlot(${i + 1}, Logistics.BeltSlots, ${o.bend})`), rot: [0, 0, 0], color: colors[item], material: "SmoothPlastic" });
        });
        objects.push({ at, yaw, parts: items });
      } else if (o.machine) {
        objects.push({ at, yaw, parts: lua.call(`Models.Machine("${o.kind}")`), lit: o.working });
      } else {
        objects.push({ at, yaw, parts: lua.call("Models.WoodenChest()") });
      }
    }
    const techs = lua.call("Research.Technologies");
    const status = ["✓ Zbadane", "Bada się: 1 min 12 s", null, null];
    const tech = (t, i) => `<div class="card" style="height:174px">
      <div style="position:absolute;left:10px;top:10px">${slot(t.unlocks[0], "", { size: 64 })}</div>
      <div style="position:absolute;left:86px;top:6px;right:134px;font-size:14px;line-height:1.3"><b>${t.name}</b> (${t.time >= 60 ? Math.floor(t.time / 60) + " min " + (t.time % 60) + " s" : t.time + " s"})<br>${t.description}</div>
      <div class="muted" style="position:absolute;left:86px;top:62px;font-size:12px">Koszt:</div>
      <div style="position:absolute;left:86px;top:80px">${ingredients(t.cost, 36)}</div>
      <div class="muted" style="position:absolute;left:86px;top:140px;right:10px;font-size:12px">Odblokowuje: ${t.unlocks.map(name).join(", ")}</div>
      <div style="position:absolute;right:10px;top:12px;width:120px">${status[i] ? `<b style="font-size:14px;color:${i ? "#ebecf0" : GREEN}">${status[i]}</b>`
        : `<span class="btn" style="display:block;text-align:center;padding:9px 0;font-size:15px;background:${t.cost.every(([id, n]) => (have[id] || 0) >= n) ? "#46825a" : "#4e5460"}">Badaj</span>`}</div></div>`;
    out["7-przetworstwo"] = { objects, camera: { pos: [cx - 6, 30, cz - 28], look: [cx + 2, 0, cz - 62], fov: 55 }, shadowRadius: 60, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="width:560px;right:16px;top:12px;bottom:40px;overflow:hidden"><div class="hd">Badania<span class="x">✕</span></div><div class="bd">
        ${techs.map(tech).join("")}</div></div>` };
  }
  // 8. The pictures of items (Shared.Icons) side by side on dark tiles, as the inventory shows them.
  {
    const objects = [{ at: [0, 0, 0], parts: [block([90, 1, 60], [0, -0.5, 0], [36, 40, 48], "SmoothPlastic")] }];
    const order = lua.call("Items.Order");
    const labels = [];
    const columns = 8, gap = 10;
    order.forEach((id, i) => {
      const parts = lua.call(`Icons.Model("${id}")`).filter((q) => !q.hidden);
      let lo = [1e9, 1e9, 1e9], hi = [-1e9, -1e9, -1e9];
      for (const q of parts) for (let k = 0; k < 3; k++) {
        const r = Math.max(...q.size) / 2;
        lo[k] = Math.min(lo[k], q.pos[k] - r); hi[k] = Math.max(hi[k], q.pos[k] + r);
      }
      const radius = Math.hypot(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]) / 2;
      const k = 4.4 / radius;
      const mid = [(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2];
      const scaled = parts.map((q) => ({ ...q, size: q.size.map((v) => v * k), pos: [(q.pos[0] - mid[0]) * k, (q.pos[1] - mid[1]) * k, (q.pos[2] - mid[2]) * k] }));
      const x = (i % columns - (columns - 1) / 2) * gap, z = (Math.floor(i / columns) - 2) * gap;
      objects.push({ at: [x, 0, z], parts: [block([9, 0.2, 9], [0, 0.1, 0], [64, 70, 84], "SmoothPlastic")] });
      objects.push({ at: [x, 0.2, z], yaw: Math.PI + 0.65, parts: scaled });
      labels.push({ at: [x, 0, z + 5.2], text: lua.call(`Items.Name("${id}")`), size: 11 });
    });
    out["8-ikony"] = { objects, camera: { pos: [0, 58, 40], look: [0, 0, 3], fov: 58 }, shadowRadius: 70, caption: "Ikony przedmiotów: małe modele 3D z src/shared/Icons.luau, które gra rysuje w kratce ekwipunku.", labels };
  }
  // 9. The workbench's window: tabs, recipe tiles, the chosen recipe's card and the queue.
  {
    let objects = square().concat(forest([0, 0, 160]));
    for (let i = 1; i <= L.Count; i++) objects = objects.concat(plot(i, { furnaces: ["lit"] }).objects);
    const W = L.Workbench;
    const locked = ["furniture_stonemason", "furniture_crusher", "furniture_foundry"];
    const recipes = lua.call("Workshop.Recipes").map((r) => ({ ...r, locked: locked.includes(r.id) }));
    const chosen = recipes.find((r) => r.id === "logistics_inserter");
    const queue = [slot("nails", "×5", { size: 56, caption: "6 s", captionColor: "#ebecf0", bar: 0.4 }), slot("logistics_belt", "×4", { size: 56, caption: "16 s" })];
    for (let i = queue.length; i < 5; i++) queue.push(slot(null, "", { size: 56, caption: "wolne" }));
    out["9-stol-warsztatowy"] = { objects, camera: { pos: [W.x - 16, 9, W.z + 4], look: [W.x + 2, 2.5, W.z - 2] }, shadowRadius: 60, hud: "1 284,50 $", caption,
      avatars: [{ at: [W.x - 5, 0, W.z + 1], yaw: -Math.PI / 2, shirt: [200, 60, 60] }],
      overlay: `<div class="win" style="width:560px;right:16px;bottom:16px"><div class="hd">Stół warsztatowy<span class="x">✕</span></div><div class="bd">
        ${tabs(["Wszystko", "Budowle", "Maszyny", "Materiały"], "Wszystko")}
        ${picker(recipes, chosen.id)}
        ${card(chosen, "", `<span class="btn" style="width:150px;text-align:center;padding:8px 0;font-size:15px">Wytwórz</span><span class="muted">Składniki zostaną zabrane od razu.</span>`)}
        <div class="muted" style="font-size:14px">Kolejka (2/5) &nbsp;·&nbsp; gotowe trafia do ekwipunku, także gdy odejdziesz</div>
        <div style="display:flex;gap:8px">${queue.join("")}</div>
      </div></div>` };
  }
  // 10. A machine's window: its recipes, the card, what is in it and the inventory.
  {
    const scene7 = out["7-przetworstwo"];
    const recipes = lua.call("Processing.Machines[Items.Foundry].recipes");
    const chosen = recipes.find((r) => r.id === "bricks") || recipes[recipes.length - 1];
    const inside = [[20, 0.4], [20, 0.4]];
    const inputs = chosen.ingredients.map(([id], i) => slot(id, `${(inside[i] || [0])[0]}/50`, { size: 56, caption: name(id) }));
    inputs.push(slot("coal", "5/50", { size: 56, caption: "Paliwo (żar 2)" }));
    out["10-maszyna"] = { ...scene7, overlay: `<div class="win" style="width:560px;right:16px;bottom:8px"><div class="hd">${name("furniture_foundry")}<span class="x">✕</span></div><div class="bd">
        <div class="muted" style="font-size:14px">Co robić:</div>
        ${picker(recipes, chosen.id, chosen.id)}
        ${card(chosen, "za wsad", `<b style="color:${GOLD};font-size:14px">▶ Maszyna robi ten przepis</b>`)}
        <div class="muted" style="font-size:14px">W maszynie (kliknij kafelek, aby wyjąć):</div>
        ${contents(inputs, 0.55, slot(chosen.id, "6/100", { size: 56, caption: "Gotowe", captionColor: "#ebecf0" }))}
        <div class="muted" style="font-size:14px">Ekwipunek: kliknij składnik albo paliwo, aby włożyć (Shift: połowę)</div>
        ${haveGrid(8, 16)}
      </div></div>` };
  }
  // 11. The market between players: items with their lowest price, the chosen item's offers.
  {
    let objects = square().concat(forest([0, 0, 160]));
    for (let i = 1; i <= L.Count; i++) objects = objects.concat(plot(i, { furnaces: ["lit"] }).objects);
    const offers = { planks: [250, 105], wood: [220, 340], iron_ingot: [1150, 48], stone: [95, 900], coal: [450, 120], nails: [320, 60], logistics_belt: [900, 12] };
    const locked = ["furniture_stonemason", "furniture_crusher", "furniture_foundry", "crushed_iron_ore", "crushed_copper_ore", "crushed_tin_ore", "sand", "bronze_ingot", "steel_ingot", "bricks", "stone_blocks"];
    const money = (c) => lua.call(`Money.Format(${c})`);
    const tiles = lua.call("Items.Order").filter((id) => lua.call(`Items.Category("${id}")`) === "materials").map((id) => {
      const o = offers[id];
      return slot(id, o ? o[1] : "", { size: 52, dim: locked.includes(id), badge: locked.includes(id) ? "🔒" : null, caption: o ? money(o[0]) : "—", captionColor: o ? GOLD : null, stroke: id === "planks" ? GOLD : null });
    });
    const row = (price, left, who, button, cls) => `<div class="row"><b class="gold" style="width:100px">${money(price)}</b><span style="width:80px;font-size:14px">${left} szt.</span><span class="muted" style="width:170px;font-size:14px">${who}</span>${button ? `<span class="btn ${cls}" style="width:100px;text-align:center">${button}</span>` : `<span class="gold" style="font-size:13px">twoja oferta</span>`}</div>`;
    out["11-rynek"] = { objects, camera: { pos: [17, 6.5, 1], look: [2, 4.5, -17] }, shadowRadius: 60, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="width:900px;left:50%;transform:translateX(-50%);top:40px;bottom:30px;overflow:hidden"><div class="hd">Rynek graczy<span class="x">✕</span></div><div class="bd">
        ${tabs(["Rynek", "Moje oferty"], "Rynek")}
        ${catTabs("materials", lua.call("Items.Order"))}
        <div style="display:flex;gap:12px">
          <div style="width:300px;flex:none"><div style="width:284px;height:32px;box-sizing:border-box;border-radius:6px;background:#181b21;border:1px solid #5a6273;padding:7px 8px;font-size:15px;color:#a0a6b2">Szukaj, np. deski</div><div class="muted" style="font-size:13px;margin:6px 0 4px">Towary (najniższa cena)</div>
            <div style="display:grid;grid-template-columns:repeat(5,52px);gap:2px 6px">${tiles.join("")}</div></div>
          <div style="flex:1;display:flex;flex-direction:column;gap:6px">
            <div class="card" style="height:100px"><div style="position:absolute;left:10px;top:12px">${slot("planks", "12", { size: 76 })}</div>
              <div style="position:absolute;left:98px;top:8px;font-weight:800;font-size:18px">Deski &nbsp;(masz 12)</div>
              <div class="gold" style="position:absolute;left:98px;top:34px;font-size:13px">Najtaniej: 2,50 $ (105 szt.) &nbsp;·&nbsp; Najwięcej płacą: 2,20 $ (50 szt.)</div>
              <div class="muted" style="position:absolute;left:98px;top:56px;font-size:13px">Handlarz: skupuje po 1,50 $, sprzedaje po 3 $</div></div>
            <div class="row" style="height:44px"><span style="font-size:14px">Ilość</span><span style="width:70px;height:32px;border-radius:6px;background:#181b21;border:1px solid #5a6273;display:flex;align-items:center;justify-content:center">40</span>
              <span style="font-size:14px">Cena za szt. ($)</span><span style="width:90px;height:32px;border-radius:6px;background:#181b21;border:1px solid #5a6273;display:flex;align-items:center;justify-content:center">2,40</span><span class="muted" style="font-size:13px">razem 96 $</span></div>
            <div style="display:flex;gap:8px;align-items:center"><span class="btn" style="width:160px;text-align:center;padding:8px 10px">Wystaw na sprzedaż</span><span class="btn alt" style="width:140px;text-align:center;padding:8px 10px">Złóż zamówienie</span><span class="muted" style="font-size:12px">Towar lub pieniądze czekają w ofercie.</span></div>
            <b style="font-size:15px">Na sprzedaż (od najtańszych): kupujesz tyle, ile wpisane w Ilość</b>
            ${row(250, 5, "Ola_Buduje", "Kup", "")}${row(300, 100, "kopacz77", "Kup", "")}${row(320, 40, "Jakub", null)}
            <b style="font-size:15px">Zamówienia (kto płaci najwięcej): sprzedajesz ze swojego ekwipunku</b>
            ${row(220, 50, "Tartak_Bartka", "Sprzedaj", "alt")}${row(180, 200, "Ola_Buduje", "Sprzedaj", "alt")}
          </div></div>
      </div></div>` };
  }
  // 12. Power: a generator fed coal by an inserter, poles wired together and crushers on them, and
  // the generator's window.
  {
    const p = plot(1, { cut: [5] });
    const objects = square().concat(p.objects);
    const { cx, cz } = p;
    const state = lua.call(`(function()
      local o, n = {}, 0
      local function add(kind, x, z, rot) n = n + 1; local obj = Logistics.New(n, kind, x + 20, z + 10, rot); table.insert(o, obj); return obj end
      local coal = add(Items.WoodenChest, 0, 1, 1); Logistics.Store(coal.items, Items.Coal, 60)
      add(Items.Inserter, 1, 1, 1)
      add(Items.Generator, 2, 0, 1)
      for _, x in ipairs({ 5, 11, 16 }) do add(Items.Pole, x, 1, 0) end
      for _, x in ipairs({ 6, 10, 15 }) do
        local c = add(Items.Crusher, x, 2, 0)
        c.machine = Processing.SetRecipe(Items.Crusher, c.machine, Items.CrushedIronOre, 0)
        c.machine = Processing.Load(Items.Crusher, c.machine, Items.IronOre, 40, 0)
      end
      Logistics.RunPowered(o, {}, 0, 0, 23.4)
      local nets = Power.Networks(o, Logistics.Sizes)
      local net = nets[1]
      local wires = {}
      for _, w in ipairs(Power.Wires(o)) do table.insert(wires, { { w[1].x, w[1].z }, { w[2].x, w[2].z } }) end
      for _, obj in ipairs(o) do
        if obj.machine then obj.working = Processing.Working(obj.kind, obj.machine, 23.4) end
        if obj.generator then obj.working = Power.Running(obj.generator) end
      end
      return { objects = o, wires = wires, net = { supply = Power.Supply(net), demand = net.demand, speed = Power.Speed(net), poles = #net.poles, generators = #net.generators, machines = #net.consumers } }
    end)()`);
    const yaws = [Math.PI, -Math.PI / 2, 0, Math.PI / 2];
    const tileAt = (x, z, size) => lua.call(`{ PlotLayout.TileCenter(${x}, ${z}, ${size}) }`);
    const sizes = lua.call("Logistics.Sizes");
    let gen = null;
    for (const o of state.objects) {
      const [ox, oz] = tileAt(o.x, o.z, sizes[o.kind] || 1);
      const at = [cx + ox, 0, cz + oz], yaw = yaws[o.rot];
      if (o.kind === "logistics_inserter") {
        const parts = lua.call("Models.Inserter()");
        objects.push({ at, yaw, parts: parts.filter((q) => q.group !== "arm") });
        objects.push({ at, yaw: yaw + Math.PI * (1 - o.swing / 4), parts: parts.filter((q) => q.group === "arm") });
      } else if (o.machine) {
        objects.push({ at, yaw, parts: lua.call(`Models.Machine("${o.kind}")`), lit: o.working });
      } else if (o.kind === "power_generator") {
        gen = at;
        objects.push({ at, yaw, parts: lua.call("Models.Generator()"), lit: o.working });
      } else if (o.kind === "power_pole") {
        objects.push({ at, yaw, parts: lua.call("Models.Pole()") });
      } else {
        objects.push({ at, yaw, parts: lua.call("Models.WoodenChest()") });
      }
    }
    const top = lua.call("Models.PoleTop");
    for (const [a, b] of state.wires) {
      const [ax, az] = tileAt(a[0], a[1], 1), [bx, bz] = tileAt(b[0], b[1], 1);
      objects.push({ at: [0, 0, 0], parts: lua.call(`Models.Wire({ ${cx + ax}, ${top}, ${cz + az} }, { ${cx + bx}, ${top}, ${cz + bz} })`) });
    }
    const n = state.net;
    const fuel = slot("coal", "37/50", { size: 56, caption: "Paliwo" });
    const power = `<div style="width:200px;height:56px;display:flex;align-items:center;font-size:22px;font-weight:800;color:${GOLD}">${Math.round(n.supply)} / 100 kW</div>`;
    out["12-prad"] = { objects, camera: { pos: [gen[0] + 4, 30, gen[2] + 44], look: [gen[0] + 26, 3, gen[2] - 2], fov: 50 }, shadowRadius: 80, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="width:520px;right:16px;bottom:16px"><div class="hd">${name("power_generator")}<span class="x">✕</span></div><div class="bd">
        <b style="color:${GREEN};font-size:14px">⚡ Pracuje i zasila sieć.</b>
        <div class="muted" style="font-size:14px">W generatorze (kliknij paliwo, aby wyjąć):</div>
        ${contents([fuel], 0.62, power)}
        <div style="font-size:14px">Sieć: ${n.poles} słup(y), ${n.generators} generator(y), ${n.machines} maszyn(y). Pobór ${n.demand} kW, moc ${n.supply} kW.</div>
        <div class="muted" style="font-size:13px">Przy pełnej mocy (100 kW) jedna sztuka starcza: Węgiel 200 s, Drewno 50 s, Pellet drzewny 40 s.</div>
        <div class="muted" style="font-size:14px">Ekwipunek: kliknij paliwo, aby włożyć (Shift: połowę)</div>
        ${haveGrid(7, 14)}
      </div></div>` };
  }
  // 13. The railway: the plot's station, a train at the platform, and the station's window.
  {
    const p = plot(1, { cut: [5] });
    const objects = square().concat(p.objects);
    const { cx, cz } = p;
    const R = lua.call("PlotLayout.Rail");
    const cargo = lua.call("{ Items.Colors[Items.IronIngot], Items.Colors[Items.Planks], Items.Colors[Items.Coal] }");
    objects.push({ at: [cx + R.x, 0, cz + R.stop], parts: lua.call(`Models.Train(3, json_decode_cargo)`.replace("json_decode_cargo", `{ ${cargo.map((c) => `{ ${c.join(",")} }`).join(",")} }`)) });
    const stock = [["coal", 340], ["iron_ingot", 120], ["planks", 85], ["stone", 600], ["sand", 45]];
    const stockTiles = stock.map(([id, n]) => slot(id, String(n), { size: 52, stroke: id === "iron_ingot" ? GOLD : null })).join("");
    const prow = (n, km, s, on) => `<div class="row" style="height:34px;${on ? "background:#6e5c28" : ""}"><span style="flex:1;font-size:14px"><b>${n}</b> &nbsp; ${km ? km + " km, " : ""}pociąg jedzie ${s} s</span><span class="btn ${on ? "alt" : ""}" style="width:90px;text-align:center">${on ? "Wybrany" : "Wybierz"}</span></div>`;
    out["13-kolej"] = { objects, camera: { pos: [cx + 78, 20, cz - 40], look: [cx + 112, 3, cz - 104], fov: 60 }, shadowRadius: 90, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="width:500px;left:16px;top:60px;bottom:30px;overflow:hidden"><div class="hd">Stacja kolejowa<span class="x">✕</span></div><div class="bd">
        ${tabs(["Magazyn", "Wyślij", "Trasy (1)"], "Wyślij")}
        <div class="muted" style="font-size:13px">Komu: na inną swoją działkę albo do gracza, którego znajdziesz po nazwie (na dowolnym serwerze).</div>
        <div style="display:flex;gap:8px"><span style="width:220px;height:30px;border-radius:6px;background:#181b21;border:1px solid #5a6273;padding:6px 8px;box-sizing:border-box;color:#a0a6b2;font-size:15px">Nazwa gracza</span><span class="btn" style="width:90px;text-align:center;padding:6px 0">Szukaj</span></div>
        ${prow("Twoja działka: Góry", 0, lua.call("Rail.OwnTrip"), true)}${prow("Ola_Buduje", 640, 32, false)}${prow("kopacz77", 1210, 61, false)}
        <div class="muted" style="font-size:13px">Co: kliknij towar na stacji.</div>
        <div style="display:flex;gap:6px">${stockTiles}</div>
        <div class="row" style="height:44px"><span style="width:80px;height:30px;border-radius:6px;background:#181b21;border:1px solid #5a6273;display:flex;align-items:center;justify-content:center">120</span><span class="gold" style="flex:1;font-size:14px">Opłata ${lua.call("Money.Format(Rail.FeeCents(0, 120))")}, ${lua.call("Rail.OwnTrip")} s</span><span class="btn" style="width:150px;text-align:center;padding:6px 0">Wyślij pociągiem</span></div>
        <b style="font-size:15px">Pociągi w drodze</b>
        <div style="font-size:13px;color:${GREEN}">⬅ od działki Góry: 400 × ${name("iron_ore")} (za 12 s)</div>
        <div style="font-size:13px;color:${GREEN}">⬅ od kopacz77: 200 × ${name("coal")} (za 41 s)</div>
        <div style="font-size:13px">➡ do Ola_Buduje: 60 × ${name("planks")} (dojedzie za 12 s)</div>
      </div></div>` };
  }
  // 14. A plot of the tundra shown on the player's place, with the window of their plots.
  {
    const p = plot(1, { biome: "tundra" });
    const { cx, cz } = p;
    const objects = square().concat(p.objects, forest([cx, cz, 260]));
    const biomes = lua.call("Lands.Biomes");
    const rgb = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;
    const drops = (list) => list.slice().reverse().map(([id, n]) => `<span style="display:inline-flex;align-items:center;gap:3px;margin-right:8px">${slot(id, "", { size: 30 })}<span style="font-size:13px">${Math.max(1, Math.round(n / 10))}%</span></span>`).join("");
    const card = (b, right) => `<div class="card" style="height:112px;padding:0"><div style="position:absolute;left:10px;top:10px;width:92px;height:92px;border-radius:8px;background:${rgb(b.ground)}"></div>
      <b style="position:absolute;left:114px;top:10px;font-size:18px">${b.name}</b><div class="muted" style="position:absolute;left:114px;top:36px;width:300px;font-size:13px;line-height:1.3">${b.text}${b.trees ? ` Drzew na start: ${b.trees}.` : ""}</div>
      <div style="position:absolute;left:114px;top:72px;display:flex">${drops(b.drops)}</div><div style="position:absolute;right:10px;top:10px">${right}</div></div>`;
    const meadow = { name: "Łąka", ground: [96, 140, 64], text: "Twoja pierwsza działka, ze stacją kolejową.", drops: lua.call("Mining.Drops") };
    out["14-dzialki"] = { objects, camera: { pos: [cx - 70, 46, cz + 60], look: [cx + 10, 0, cz - 30], fov: 60 }, shadowRadius: 140, hud: "61 284,50 $", caption,
      overlay: `<div class="win" style="width:640px;right:16px;top:20px;bottom:20px;overflow:hidden"><div class="hd">Moje działki<span class="x">✕</span></div><div class="bd">
        <div class="muted" style="font-size:14px">Na serwerze stoi jedna twoja działka naraz. Te, których nie widać, dalej pracują i po powrocie wszystko jest przeliczone.</div>
        ${card(meadow, `<span class="btn" style="width:150px;display:inline-block;text-align:center;padding:7px 0">Pokaż tutaj</span>`)}
        ${card(biomes.tundra, `<b style="color:${GREEN};font-size:15px">Tu stoi</b>`)}
        <div style="font-size:16px"><b>Kup nową działkę</b> za <span class="gold">${lua.call("Money.Format(Lands.Prices[2])")}</span> <span class="muted">(masz 61 284,50 $)</span></div>
        ${card(biomes.desert, `<span class="btn" style="width:150px;display:inline-block;text-align:center;padding:7px 0;background:#4e5460">Kup: Pustynia</span>`)}
      </div></div>` };
  }
  // 15. A plot of the desert and one of the mountains, from above.
  {
    const a = plot(1, { biome: "desert" });
    const objects = square().concat(a.objects, plot(2, { biome: "mountains" }).objects, plot(8, { biome: "forest" }).objects, forest());
    out["15-biomy"] = { objects, camera: { pos: [a.cx - 360, 300, a.cz + 40], look: [a.cx - 20, 0, a.cz], fov: 60 }, shadowRadius: 500, fog: [900, 2000], hud: "1 284,50 $", caption,
      labels: [{ at: [a.cx, 20, a.cz], text: "Pustynia", size: 18 }] };
  }
  // 16. The company window of a member, over their plot.
  {
    const p = plot(1);
    const { cx, cz } = p;
    const objects = square().concat(p.objects, forest([cx, cz, 260]));
    const now = 1700000000 + 3 * 86400;
    const c = lua.call(`(function()
      local now = ${now}
      local n = 0
      local function step(c, a) n = n + 1; a.tx = "t" .. n; a.at = a.at or now - 3600 * (20 - n); return (Companies.Apply(c, a)) end
      local c = step(nil, { kind = "create", id = "huta", name = "Huta Pod Lasem", owner = "1", ownerName = "Ola_Buduje", cents = Companies.FoundingCents })
      c = step(c, { kind = "join", member = "2", name = "kopacz77" })
      c = step(c, { kind = "join", member = "3", name = "Ty" })
      c = step(c, { kind = "deposit", member = "2", cents = 600000 })
      c = step(c, { kind = "deposit", member = "3", cents = 250000 })
      local o = Companies.Orders("huta", Companies.Week(now))
      c = step(c, { kind = "deliver", member = "2", order = 1, quantity = math.floor(o[1].quantity / 2) })
      c = step(c, { kind = "deliver", member = "3", order = 2, quantity = o[2].quantity })
      c = step(c, { kind = "project", member = "1", project = "hq" })
      c = step(c, { kind = "contribute", member = "2", item = Items.StoneBlocks, quantity = 500 })
      c = step(c, { kind = "contribute", member = "3", item = Items.Beams, quantity = 260 })
      c = step(c, { kind = "contribute", member = "1", item = Items.Bricks, quantity = 80 })
      local hq = {}
      for i, part in ipairs(Companies.Project("hq").parts) do hq[i] = { item = part[1], quantity = part[2], delivered = c.project.delivered[part[1]] or 0 } end
      local orders = {}
      for i, x in ipairs(o) do if i <= Companies.OrderCount(c, now) then orders[i] = { item = x.item, quantity = x.quantity, left = Companies.Left(c, i, now), rewardCents = x.rewardCents } end end
      local members = {}
      for id, m in pairs(c.members) do members[#members + 1] = { name = m.name, shares = m.shares, owner = id == c.owner } end
      table.sort(members, function(a, b) return a.shares > b.shares end)
      local log = {}
      for i = #c.log, 1, -1 do log[#log + 1] = c.log[i].text end
      local mine, value = Companies.Stake(c, "3")
      return { name = c.name, cash = Money.Format(c.cashCents), price = Money.Format(Companies.SharePrice(c)), shares = c.shares, mine = mine, value = Money.Format(value),
        orders = orders, members = members, log = log, hq = hq, hqText = Companies.Project("hq").text, weekLeft = (Companies.Week(now) + 1) * Companies.WeekSeconds - now }
    end)()`);
    const pct = (n) => Math.round(n / c.shares * 1000) / 10;
    const days = Math.floor(c.weekLeft / 86400), hours = Math.floor((c.weekLeft % 86400) / 3600);
    const input = (text, w) => `<span style="width:${w}px;height:30px;border-radius:6px;background:#181b21;border:1px solid #5a6273;padding:6px 8px;box-sizing:border-box;color:#a0a6b2;font-size:15px">${text}</span>`;
    const order = (o) => {
      const give = Math.min(have[o.item] || 0, o.left);
      const label = o.left <= 0 ? "Wykonane" : give > 0 ? "Oddaj " + give : "Nie masz";
      return `<div class="row" style="height:46px">${slot(o.item, "", { size: 36 })}<span style="flex:1;font-size:14px"><b>${name(o.item)}</b> &nbsp; ${o.quantity - o.left} / ${o.quantity} &nbsp; płaci ${lua.call(`Money.Format(${o.rewardCents})`)} za sztukę</span><span class="btn" style="width:150px;text-align:center;padding:8px 0;${o.left > 0 && give > 0 ? "" : "background:#4e5460"}">${label}</span></div>`;
    };
    out["16-spolka"] = { objects, camera: { pos: [cx - 60, 40, cz + 70], look: [cx + 10, 0, cz - 20], fov: 60 }, shadowRadius: 140, hud: "8 421,00 $", caption,
      overlay: `<div class="win" style="width:720px;right:16px;top:14px;bottom:14px;overflow:hidden"><div class="hd">Spółka<span class="x">✕</span></div><div class="bd">
        <div class="card" style="height:96px;padding:0;position:relative"><b style="position:absolute;left:12px;top:8px;font-size:22px">${c.name}</b>
          <div class="muted" style="position:absolute;left:12px;top:38px;font-size:14px">Założyciel: Ola_Buduje &nbsp; Wspólników: ${c.members.length}/${lua.call("Companies.MaxMembers")}</div>
          <div class="gold" style="position:absolute;left:12px;top:60px;font-size:14px">Kasa: <b>${c.cash}</b> &nbsp; Cena udziału: <b>${c.price}</b> &nbsp; Twoje udziały: <b>${c.mine}</b> (${pct(c.mine)}%), warte ${c.value}</div></div>
        <b style="font-size:17px">Udziały</b>
        <div class="row" style="height:40px">${input("Kwota w $", 120)}<span class="btn" style="width:130px;text-align:center">Kup udziały</span>${input("Ile udziałów", 120)}<span class="btn alt" style="width:110px;text-align:center">Sprzedaj</span></div>
        <b style="font-size:17px">Zlecenia tygodnia (zostało ${days} d ${hours} h)</b>
        <div class="muted" style="font-size:13px">Spółka dostaje za towar więcej niż u handlarza. Ty dostajesz udziały warte tyle, ile dałby handlarz, a reszta podnosi cenę udziałów wszystkich.</div>
        ${c.orders.map(order).join("")}
        <b style="font-size:17px">Wielkie projekty</b>
        <div class="row" style="height:40px;font-size:13px"><span><b>Siedziba spółki</b> &nbsp;${c.hqText} &nbsp;<i>zbieranie części</i></span></div>
        ${c.hq.map((p) => { const left = p.quantity - p.delivered; const give = Math.min(have[p.item] || 0, left);
          return `<div class="row" style="height:40px">${slot(p.item, "", { size: 32 })}<span style="flex:1;font-size:14px">${name(p.item)} &nbsp; ${p.delivered} / ${p.quantity}</span><span class="btn" style="width:150px;text-align:center;padding:8px 0;${left > 0 && give > 0 ? "" : "background:#4e5460"}">${left <= 0 ? "Zebrane" : give > 0 ? "Oddaj " + give : "Nie masz"}</span></div>`; }).join("")}
        <b style="font-size:17px">Wspólnicy</b>
        ${c.members.map((m) => `<div class="row" style="height:34px;font-size:14px"><span><b>${m.name}</b>${m.owner ? " (założyciel)" : ""} &nbsp; ${m.shares} udziałów, ${pct(m.shares)}%</span></div>`).join("")}
      </div></div>` };
  }
  // The windows' item pictures: every item's parts, drawn by index.html.
  const icons = {};
  for (const id of lua.call("Items.Order")) icons[id] = lua.call(`Icons.Model("${id}")`);
  const iconView = lua.call("Icons.ViewDirection");
  for (const v of Object.values(out)) if (v.overlay) Object.assign(v, { icons, iconView });
  return out;
}

async function shoot() {
  const { chromium } = require("playwright");
  const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
  const out = path.join(__dirname, "../../docs/screenshots");
  fs.mkdirSync(out, { recursive: true });
  // `node tools/preview/scene.js 3 9` takes only the views whose names start with 3 or 9.
  const only = process.argv.slice(2);
  for (const [name, scene] of Object.entries(views())) {
    if (only.length && !only.some((o) => name.startsWith(o + "-"))) continue;
    // A new page for each scene: init scripts stay on a page and would all run again.
    const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
    page.on("pageerror", (e) => console.log("page error:", e.message));
    await page.route("**/three.min.js", (route) => route.fulfill({ path: path.join(path.dirname(require.resolve("three")), "three.min.js"), contentType: "text/javascript" }));
    await page.addInitScript((s) => { window.SCENE = s; }, scene);
    await page.goto("file://" + path.join(__dirname, "index.html"), { timeout: 120000 });
    await page.waitForFunction(() => document.title === "ready", null, { timeout: 120000 });
    await page.screenshot({ path: path.join(out, name + ".png") });
    console.log("saved", name);
    await page.close();
  }
  await browser.close();
}

if (require.main === module) shoot();
module.exports = { views };
