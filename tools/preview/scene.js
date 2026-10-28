// Builds the preview scenes from the game's own models and layout (src/shared) the way the server
// puts them together (Services/World.luau, Services/Plots.luau), and takes the screenshots in
// docs/screenshots. Needs fengari, three and Playwright: `npm install`, then
// `node tools/preview/scene.js` (Playwright's Chromium must be installed).
const fs = require("fs");
const path = require("path");
const { luaShared } = require("./shared.js");

const lua = luaShared();
const L = lua.call("{ Count = PlotLayout.Count, Size = PlotLayout.Size, Ring = PlotLayout.Ring, Mines = PlotLayout.Mines,"
  + " Trees = PlotLayout.Trees, FurnaceSlots = PlotLayout.FurnaceSlots, Stall = PlotLayout.Stall, Workbench = PlotLayout.Workbench,"
  + " Fountain = PlotLayout.Fountain, SquareSpawn = PlotLayout.SquareSpawn, Spawn = PlotLayout.Spawn }");
const center = (i) => lua.call(`{ PlotLayout.Center(${i}) }`);

const cyl = (len, d, pos, color, material) => ({ shape: "Cylinder", size: [len, d, d], pos, rot: [0, 0, Math.PI / 2], color, material });
const block = (size, pos, color, material, yaw = 0) => ({ shape: "Block", size, pos, rot: [0, yaw, 0], color, material });

function square() {
  const objects = [];
  const big = 2 * L.Ring + L.Size + 80;
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

// One plot as Plots.buildPlot puts it together; `opts` says which trees are cut and which slots
// have a furnace (and whether it is lit).
function plot(index, opts = {}) {
  const [cx, cz] = center(index);
  const objects = [];
  objects.push({ at: [cx, 0, cz], parts: [block([L.Size, 1, L.Size], [0, -0.45, 0], [116, 158, 78], "Grass")] });
  objects.push({ at: [cx, 0, cz], parts: lua.call(`Models.PlotDecor(${index * 100}, PlotLayout.Size, PlotLayout.OpenSides(${index}), PlotLayout.FurnaceSlots, PlotLayout.Grid)`) });
  const half = L.Size / 2, d = Math.hypot(cx, cz), tx = -cx / d, tz = -cz / d;
  const sign = [cx + tx * (half - 5) + tz * 6, 0, cz + tz * (half - 5) - tx * 6];
  // CFrame.lookAt(at, at + toSquare): the front (-z) faces the square.
  objects.push({ at: sign, yaw: Math.atan2(-tx, -tz), parts: lua.call(`Models.Signpost(${index})`) });
  L.Mines.forEach((m, k) => objects.push({ at: [cx + m.x, 0, cz + m.z], yaw: Math.PI, parts: lua.call(`Models.Mine(${index * 10 + k + 1})`) }));
  L.Trees.forEach((t, k) => {
    const seed = index * 20 + k + 1;
    objects.push({ at: [cx + t.x, 0, cz + t.z], yaw: (seed % 7) * 0.9, parts: lua.call(`Models.Tree(${seed})`), hideGroup: (opts.cut || []).includes(k) ? "crown" : null });
  });
  L.FurnaceSlots.forEach((s, k) => {
    objects.push({ at: [cx + s.x, 0, cz + s.z], parts: [cyl(0.3, 8, [0, 0.15, 0], [156, 150, 140], "Slate")] });
    const f = (opts.furnaces || [])[k];
    if (f) objects.push({ at: [cx + s.x, 0, cz + s.z], yaw: Math.PI, parts: lua.call("Models.Furnace()"), lit: f === "lit" });
  });
  return { objects, cx, cz, sign };
}

const caption = "Podgląd Factory World 3D: modele wprost z kodu gry (src/shared/Models.luau). W Robloxie oświetlenie, materiały i postacie wyglądają nieco inaczej.";
const sw = (c) => `<span class="sw" style="background:rgb(${c})"></span>`;

function views() {
  const out = {};
  // 1. The square and all plots from above.
  {
    let objects = square();
    for (let i = 1; i <= L.Count; i++) objects = objects.concat(plot(i, { furnaces: ["lit", i % 2 ? "lit" : "cold", i % 3 ? "cold" : null], cut: i % 2 ? [1, 4] : [] }).objects);
    out["1-plac-i-dzialki"] = { objects, camera: { pos: [120, 190, 250], look: [0, 0, 10], fov: 60 }, shadowRadius: 260, fog: [400, 900], hud: "1 284,50 $", caption,
      labels: [{ at: [L.Stall.x, 14, L.Stall.z], text: "Handlarz", color: "#ffe678", size: 15 }] };
  }
  // 2. Mining on the player's plot.
  {
    const p = plot(1, { furnaces: ["lit", "lit", "cold"], cut: [0, 5] });
    const objects = square().concat(p.objects, plot(2, { furnaces: ["lit"] }).objects, plot(8, { furnaces: ["cold", "cold"] }).objects);
    const { cx, cz } = p;
    out["2-kopanie-na-dzialce"] = { objects, camera: { pos: [cx + 11, 13, cz - 2], look: [cx - 1, 3, cz - 26] }, shadowRadius: 70, hud: "1 284,50 $", caption,
      avatars: [{ at: [cx + 0.5, 0, cz - 15.5], yaw: Math.PI, shirt: [200, 60, 60], pose: -1.9 }],
      labels: [{ at: [cx + 0, 13, cz - 32], text: "Kopalnia 37/50" }, { at: [cx - 25, 13, cz - 30], text: "Kopalnia 50/50" }],
      prompts: [{ at: [cx + 5, 8, cz - 19], action: "Kop", object: "Kopalnia", progress: 0.62 }],
      overlay: `<div class="toast">+1 Kamień, +1 Ruda żelaza</div>` };
  }
  // 3. Furnaces with the furnace window.
  {
    const p = plot(1, { furnaces: ["lit", "lit", "cold", "lit"], cut: [5] });
    const objects = square().concat(p.objects);
    const { cx, cz } = p;
    out["3-piec"] = { objects, camera: { pos: [cx + 6, 9, cz + 31], look: [cx + 17, 3, cz + 14] }, shadowRadius: 50, hud: "1 284,50 $", caption,
      avatars: [{ at: [cx + 13, 0, cz + 22], yaw: Math.PI + 0.3, shirt: [200, 60, 60] }],
      overlay: `<div class="win" style="width:440px;right:16px;bottom:40px"><div class="hd">Piec kamienny<span class="x">✕</span></div><div class="bd">
        <div>Ruda: Ruda żelaza × 23 / 50</div><div>Węgiel: 4 / 50 &nbsp; (żar na 3 szt.)</div><div><b>Gotowe: Sztabka żelaza × 12</b></div>
        <div class="bar"><i style="width:64%"></i></div><div class="muted">Włóż z ekwipunku:</div>
        <div class="row">${sw("40,40,44")}<span style="width:190px">Węgiel (31)</span><span class="btn">Włóż wszystko</span></div>
        <div class="row">${sw("196,112,60")}<span style="width:190px">Ruda miedzi (8)</span><span class="btn">Włóż wszystko</span></div>
        <div style="display:flex;gap:8px;margin-top:4px"><span class="btn">Weź sztabki</span><span class="btn alt">Weź rudę</span><span class="btn alt">Weź węgiel</span><span class="btn red">Schowaj</span></div>
      </div></div>` };
  }
  // 4. The merchant's square.
  {
    let objects = square();
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
      local function add(kind, x, z, rot) n = n + 1; local obj = Logistics.New(n, kind, x, z, rot); table.insert(o, obj); return obj end
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
      local furnace = { id = 99, tile = { x = 9, z = 1 }, rot = 0, state = Smelting.Empty() }
      Logistics.Run(o, { furnace }, 0, 41.4)
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
      } else {
        objects.push({ at, yaw, parts: models[o.kind] });
      }
      if (o.belt) {
        const items = [];
        o.belt.forEach((item, i) => {
          if (!item) return;
          const pos = lua.call(`Models.BeltSlot(${i + 1}, Logistics.BeltSlots)`);
          items.push({ shape: "Ball", size: [0.75, 0.75, 0.75], pos, rot: [0, 0, 0], color: colors[item], material: "SmoothPlastic" });
        });
        objects.push({ at, yaw, parts: items });
      }
    }
    const [fx, fz] = tileAt(state.furnace.x, state.furnace.z, 2);
    objects.push({ at: [cx + fx, 0, cz + fz], yaw: Math.PI, parts: lua.call("Models.Furnace(true)"), lit: state.lit });
    // The see-through ghost of the next belt under the pointer.
    const [gx, gz] = tileAt(13, 2, 1);
    const ghost = models.logistics_inserter.map((q) => ({ ...q, transparency: 0.3 })).concat(lua.call("Models.BuildMarker(Items.Inserter, PlotLayout.Grid.tile)"));
    objects.push({ at: [cx + gx, 0, cz + gz], yaw: yaws[1], parts: ghost });
    const btn = (t, on) => `<span class="btn${on ? "" : " alt"}" style="width:140px;text-align:center;white-space:nowrap">${t}</span>`;
    out["6-budowanie"] = { objects, camera: { pos: [cx + 10, 34, cz + 18], look: [cx + 8, 0, cz - 6], fov: 55 }, shadowRadius: 60, hud: "1 284,50 $", caption,
      overlay: `<div class="win" style="left:50%;transform:translateX(-50%);bottom:16px;width:760px"><div class="bd" style="padding-top:10px">
        <div style="display:flex;gap:6px">${btn("Taśmociąg (6)")}${btn("Podajnik (2)", true)}${btn("Drewniana skrzynia (1)")}${btn("Piec kamienny (0)")}<span class="btn red">Rozbiórka [X]</span><span class="btn alt">Obróć [R]</span></div>
        <div class="muted" style="margin-top:8px">Kliknij, by postawić (przeciągnij, by ułożyć taśmę). 1–4 wybór, R obrót, X rozbiórka, B koniec.</div>
      </div></div>` };
  }
  return out;
}

async function shoot() {
  const { chromium } = require("playwright");
  const browser = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  page.on("pageerror", (e) => console.log("page error:", e.message));
  await page.route("**/three.min.js", (route) => route.fulfill({ path: path.join(path.dirname(require.resolve("three")), "three.min.js"), contentType: "text/javascript" }));
  const out = path.join(__dirname, "../../docs/screenshots");
  fs.mkdirSync(out, { recursive: true });
  for (const [name, scene] of Object.entries(views())) {
    await page.addInitScript((s) => { window.SCENE = s; }, scene);
    await page.goto("file://" + path.join(__dirname, "index.html"));
    await page.waitForFunction(() => document.title === "ready", null, { timeout: 120000 });
    await page.screenshot({ path: path.join(out, name + ".png") });
    console.log("saved", name);
  }
  await browser.close();
}

if (require.main === module) shoot();
module.exports = { views };
