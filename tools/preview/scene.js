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

function square() {
  const objects = [];
  const big = 2 * lua.call("PlotLayout.GroundHalf()");
  objects.push({ at: [0, 0, 0], parts: [
    block([big, 2, big], [0, -1.5, 0], [92, 136, 66], "Grass"),
    cyl(1, 64, [0, -0.45, 0], [168, 160, 148], "Cobblestone"),
    cyl(1, 22, [0, -0.4, 0], [190, 184, 172], "Pavement"),
    cyl(0.4, 7, [L.SquareSpawn.x, 0.1, L.SquareSpawn.z], [200, 186, 150], "Marble"),
  ] });
  objects.push({ at: [L.Fountain.x, 0, L.Fountain.z], parts: lua.call("Models.Fountain()") });
  objects.push({ at: [L.Stall.x, 0, L.Stall.z], yaw: L.Stall.yaw, parts: lua.call("Models.Stall()") });
  // The merchant stands 2.6 studs behind the counter (CFrame.new(0, 0, 2.6) in the stall's frame).
  const s = Math.sin(L.Stall.yaw), c = Math.cos(L.Stall.yaw);
  objects.push({ at: [L.Stall.x + 2.6 * s, 0, L.Stall.z + 2.6 * c], yaw: L.Stall.yaw, parts: lua.call("Models.Merchant()") });
  objects.push({ at: [L.Workbench.x, 0, L.Workbench.z], yaw: L.Workbench.yaw, parts: lua.call("Models.Workbench()") });
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
  objects.push({ at: [cx, 0, cz], parts: [block([L.Size, 1, L.Size], [0, -0.45, 0], [116, 158, 78], "Grass")] });
  objects.push({ at: [cx, 0, cz], parts: lua.call(`Models.PlotDecor(${index * 100}, PlotLayout.Size, PlotLayout.OpenSides(${index}))`) });
  const half = L.Size / 2, d = Math.hypot(cx, cz), tx = -cx / d, tz = -cz / d;
  const sign = [cx + tx * (half - 5) + tz * 6, 0, cz + tz * (half - 5) - tx * 6];
  // CFrame.lookAt(at, at + toSquare): the front (-z) faces the square.
  objects.push({ at: sign, yaw: Math.atan2(-tx, -tz), parts: lua.call(`Models.Signpost(${index})`) });
  L.Mines.forEach((m, k) => objects.push({ at: [cx + m.x, 0, cz + m.z], yaw: Math.PI, parts: lua.call(`Models.Mine(${index * 10 + k + 1})`) }));
  L.WildTrees.forEach((t, k) => {
    const id = index * 20 + k + 1;
    const [x, z] = lua.call(`{ PlotLayout.TileCenter(${t.x}, ${t.z}, 1) }`);
    // As Grid.show: the tile's yaw (pi for rotation 0) and a turn of its own.
    const yaw = Math.PI + (id % 7) * 0.9;
    const sapling = (opts.cut || []).includes(k);
    objects.push({ at: [cx + x, 0, cz + z], yaw, parts: lua.call(sapling ? `Models.Sapling(${id})` : `Models.Tree(${id})`) });
  });
  L.FurnaceSlotTiles.forEach((t, k) => {
    const f = (opts.furnaces || [])[k];
    const [x, z] = lua.call(`{ PlotLayout.TileCenter(${t.x}, ${t.z}, 2) }`);
    if (f) objects.push({ at: [cx + x, 0, cz + z], yaw: Math.PI, parts: lua.call("Models.Furnace(true)"), lit: f === "lit" });
  });
  return { objects, cx, cz, sign };
}

const caption = "Podgląd Factory World 3D: modele wprost z kodu gry (src/shared/Models.luau). W Robloxie oświetlenie, materiały i postacie wyglądają nieco inaczej.";
const sw = (c) => `<span class="sw" style="background:rgb(${c})"></span>`;

// Tiles of an item grid as the game draws them (client/Ui/ItemGrid.luau): a picture made of shapes
// in the item's colour and the count in the corner; `entries` are [id, quantity], padded to `count`.
function itemGrid(entries, columns, count) {
  const colors = lua.call("Items.Colors");
  const c = (id, k = 1) => `rgb(${colors[id].map((v) => Math.min(255, Math.round(v * k))).join(",")})`;
  const icon = (id) => {
    if (id.endsWith("_ore") || id === "coal" || id === "stone") {
      const base = id === "coal" ? c(id) : "rgb(128,124,118)";
      const dots = id.endsWith("_ore") ? [[30, 35], [62, 55], [42, 72]].map(([x, y]) => `<i style="position:absolute;left:${x - 12}%;top:${y - 14}%;width:24%;height:28%;border-radius:50%;background:${c(id, 1.1)}"></i>`).join("") : "";
      return `<i style="position:absolute;left:11%;top:22%;width:78%;height:66%;border-radius:40%;background:${base}">${dots}</i>`;
    }
    if (id.endsWith("_ingot")) return `<i style="position:absolute;left:9%;top:38%;width:82%;height:40%;border-radius:15%;background:${c(id, 0.8)}"><i style="position:absolute;left:10%;top:0;width:80%;height:45%;border-radius:20%;background:${c(id, 1.15)}"></i></i>`;
    if (id.startsWith("tool_")) return `<i style="position:absolute;left:43%;top:15%;width:14%;height:80%;border-radius:30%;background:#8c603c;transform:rotate(35deg)"></i><i style="position:absolute;left:32%;top:23%;width:60%;height:18%;border-radius:30%;background:${id === "tool_axe" ? "#aab0ba" : c(id)};transform:rotate(35deg)"></i>`;
    if (/^(furniture|logistics|storage)_/.test(id)) return `<i style="position:absolute;left:10%;top:20%;width:80%;height:70%;border-radius:12%;background:${c(id)}"><i style="position:absolute;left:25%;top:38%;width:50%;height:40%;border-radius:15%;background:${c(id, 0.6)}"></i></i><i style="position:absolute;left:5%;top:14%;width:90%;height:12%;border-radius:30%;background:${c(id, 0.75)}"></i>`;
    return `<i style="position:absolute;left:14%;top:16%;width:72%;height:72%;border-radius:18%;background:linear-gradient(150deg,${c(id, 1.2)},${c(id, 0.75)})"></i>`;
  };
  const tiles = [];
  for (let i = 0; i < count; i++) {
    const e = entries[i];
    tiles.push(`<div style="position:relative;width:54px;height:54px;border-radius:6px;background:#1a1d24;border:1px solid #464e5e">${e ? `<div style="position:absolute;left:8%;top:6%;width:84%;height:84%">${icon(e[0])}</div><b style="position:absolute;right:4px;bottom:2px;font-size:13px;color:#fff;text-shadow:0 0 3px #000">${e[1]}</b>` : ""}</div>`);
  }
  return `<div style="display:grid;grid-template-columns:repeat(${columns},54px);gap:4px;margin:4px 0">${tiles.join("")}</div>`;
}

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
        <div>Ruda: Ruda żelaza × 23 / 50</div><div>Węgiel: 4 / 50 &nbsp; (żar na 3 szt.)</div><div><b>Gotowe: Sztabka żelaza × 12</b></div>
        <div class="bar"><i style="width:64%"></i></div><div class="muted">Ekwipunek: kliknij rudę albo węgiel, aby włożyć (Shift: połowę)</div>
        ${itemGrid([["tool_pickaxe", 1], ["tool_axe", 1], ["coal", 31], ["copper_ore", 8], ["iron_ingot", 12], ["stone", 126], ["wood", 22], ["sapling", 3], ["logistics_belt", 6], ["logistics_inserter", 2], ["storage_wooden_chest", 1], ["tin_ore", 4], ["nails", 15]], 7, 14)}
        <div style="display:flex;gap:8px;margin-top:4px"><span class="btn">Weź sztabki</span><span class="btn alt">Weź rudę</span><span class="btn alt">Weź węgiel</span><span class="btn red">Schowaj</span></div>
      </div></div>` };
  }
  // 4. The merchant's square.
  {
    let objects = square().concat(forest([0, 0, 160]));
    for (let i = 1; i <= L.Count; i++) objects = objects.concat(plot(i, { furnaces: ["lit"] }).objects);
    const rows = [["168,110,90", "Ruda żelaza (14)", "6 $"], ["40,40,44", "Węgiel (31)", "4 $"], ["140,140,140", "Kamień (126)", "1 $"], ["160,164,170", "Sztabka żelaza (12)", "10 $"], ["133,94,66", "Drewno (22)", "2 $"]];
    out["4-handlarz"] = { objects, camera: { pos: [17, 6.5, 1], look: [2, 4.5, -17] }, shadowRadius: 60, hud: "1 284,50 $", caption,
      avatars: [{ at: [4, 0, -10], yaw: Math.PI + 0.4, shirt: [200, 60, 60] }],
      labels: [{ at: [L.Stall.x, 13.5, L.Stall.z], text: "Handlarz", color: "#ffe678", size: 20 }, { at: [L.Workbench.x, 7.5, L.Workbench.z], text: "Stół warsztatowy", color: "#dce6ff", size: 15 }],
      overlay: `<div class="win" style="width:500px;right:16px;bottom:40px"><div class="hd">Handlarz<span class="x">✕</span></div><div class="bd">
        <div style="display:flex;gap:8px"><span class="btn" style="width:100px;text-align:center">Sprzedaj</span><span class="btn off" style="width:100px;text-align:center">Kup</span></div>
        ${rows.map(([c, n, p]) => `<div class="row">${sw(c)}<span style="width:160px">${n}</span><span class="gold" style="width:50px">${p}</span><span class="btn">Sprzedaj 1</span><span class="btn alt">Wszystko</span></div>`).join("")}
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
    const status = ["Zbadane", "Bada się: 1 min 12 s", null, null];
    const tech = (t, i) => `<div class="row" style="align-items:flex-start;padding:6px 8px;height:auto">${sw(colors[t.unlocks[0]].join(","))}
      <span style="width:390px;font-size:13px;line-height:1.35"><b>${t.name}</b> (${t.time >= 60 ? t.time / 60 + " min" : t.time + " s"})<br>${t.description}<br>
      <span class="muted">Koszt: ${t.cost.map((c) => c[1] + " × " + lua.call(`Items.Name("${c[0]}")`)).join(", ")}</span></span>
      ${status[i] ? `<b style="width:110px;font-size:13px">${status[i]}</b>` : `<span class="btn" style="width:70px;text-align:center">Badaj</span>`}</div>`;
    out["7-przetworstwo"] = { objects, camera: { pos: [cx - 6, 30, cz - 28], look: [cx + 2, 0, cz - 62], fov: 55 }, shadowRadius: 60, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="width:560px;right:16px;bottom:40px"><div class="hd">Badania<span class="x">✕</span></div><div class="bd">
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
  return out;
}

async function shoot() {
  const { chromium } = require("playwright");
  const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
  const out = path.join(__dirname, "../../docs/screenshots");
  fs.mkdirSync(out, { recursive: true });
  for (const [name, scene] of Object.entries(views())) {
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
