extends Node2D
## Inside one of the player's plots: 250 × 250 tiles of the biome's ground with its trees, rocks
## and dunes, the railway along the top with the plot's station and, on a mountain plot, its mines.
## The character walks with WSAD or by clicking; clicking a tree, rock or dune walks up to it and
## works it with the tool in hand, and a mine is worked with a pickaxe for ore.
## The station window loads goods from the inventory and sends them by train to other plots.
## A workbench, a research table, a furnace or a machine that processes crops (mill, oil press, pickling barrel,
## bakery, field kitchen) from the inventory can be put on a free tile and used there, and so can
## belts and inserters (turned with R) that move items between machines and chests, piles and silos.
## A computer put on the plot opens the market there, as in the garage.
## A forester's building (hut, lodge, forestry station) stands on 3 × 3 tiles and keeps a forest
## around itself: it plants saplings, cuts the grown trees and keeps the wood until taken out;
## a sawmill saws the wood into planks, beams, pellets and plywood.
## On a pasture (any plot but a desert or a glacier) an animal from the inventory is let out on a
## free tile, fed crops from a menu and, after its time, gives eggs, wool (cut with shears) or milk.

## Keyboard actions of this screen: name and keys.
const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"inventory": [KEY_I],
	"station": [KEY_T],
	"company": [KEY_K],
	"bank": [KEY_B],
	"tool": [KEY_Q],
	"plant": [KEY_P],
	"upgrade_mine": [KEY_U],
	"cancel": [KEY_ESCAPE],
	"world_map": [KEY_N],
	"garage": [KEY_G],
	"rotate": [KEY_R],
	"market": [KEY_M],
	"stats": [KEY_L],
	"achievements": [KEY_O],
	"character": [KEY_C],
}

const LAYOUT_FILE := "res://art/plot/layout.json"
## Pixels of one tile on screen; a tile is drawn as 2 × 2 m at 32 px per metre, seen at 45°.
const TILE := Vector2(64, 45)
## The character is rendered for the garage at 96 px per metre.
const PLAYER_SCALE := 1.0 / 3.0
const LIGHT := Color(0.78, 0.76, 0.8)
## Tiles per second.
const SPEED := 3.2
## Half the width of the body, in tiles.
const RADIUS := 0.25
## How close (tiles, centre to centre) the player must be to work a tile, and to use the station.
const REACH := 1.75
## Holding the right mouse button (or a finger, on a touch screen) this long on a placed object puts it back into the
## inventory; a finger may wander this many pixels before the hold is called off.
const HOLD_TO_PICK_UP := 1.0
const HOLD_SLIP := 24.0
const STATION_REACH := 2.5
## Tiles are drawn in square chunks around the player.
const CHUNK := 16
const CHUNK_RADIUS := 2
const MIN_ZOOM := 0.5
const MAX_ZOOM := 1.5

## What stands on a tile, as the server numbers it.
const NONE := 0
const TREE := 1
const ROCK := 2
const DUNE := 3
const RAIL := 4
const STATION := 5
const BUSH := 6
const MINE := 7
const WATER := 8
const FLOTSAM := 9
## The glacier's own: blocks of ice, meteorites, crevasses (and the bridges laid over them) and the snowdrifts
## a blizzard's avalanches leave, also over what stands on the plot.
const ICE_BLOCK := 10
const METEORITE := 11
const CREVASSE := 12
const BRIDGE := 13
const SNOWDRIFT := 14
## Trees of other kinds than the pine (TREE, a palm in an oasis), and mushrooms on the floor of an old forest, picked by hand.
const SPRUCE_TREE := 15
const BIRCH_TREE := 16
const OAK_TREE := 17
const LINDEN_TREE := 18
const MUSHROOMS := 19
const TREES := [TREE, SPRUCE_TREE, BIRCH_TREE, OAK_TREE, LINDEN_TREE]
## The tile each kind of planted tree grows into, by the server's id of its kind, and their names.
const SPECIES_TILES := {"pine": TREE, "spruce": SPRUCE_TREE, "birch": BIRCH_TREE, "oak": OAK_TREE, "linden": LINDEN_TREE}
const SPECIES_NAMES := {"pine": "Sosna", "spruce": "Świerk", "birch": "Brzoza", "oak": "Dąb", "linden": "Lipa"}
## Saplings of every kind: the plain one grows a pine.
const SAPLINGS := ["sapling", "sapling_spruce", "sapling_birch", "sapling_oak", "sapling_linden"]
const INSECTICIDE := "insecticide"

const SPRITES := {
	TREE: ["tree_0", "tree_1", "tree_2"],
	SPRUCE_TREE: ["spruce_0", "spruce_1"],
	BIRCH_TREE: ["birch_0", "birch_1"],
	OAK_TREE: ["oak_0", "oak_1"],
	LINDEN_TREE: ["linden_0", "linden_1"],
	MUSHROOMS: ["mushrooms_0", "mushrooms_1"],
	ROCK: ["rock_0", "rock_1", "rock_2"],
	DUNE: ["dune_0", "dune_1"],
	BUSH: ["bush_0", "bush_1"],
	FLOTSAM: ["flotsam_0", "flotsam_1", "flotsam_2"],
	ICE_BLOCK: ["ice_block_0", "ice_block_1"],
	METEORITE: ["meteorite_0"],
	SNOWDRIFT: ["snowdrift_0", "snowdrift_1"],
}
const SOLID := [TREE, SPRUCE_TREE, BIRCH_TREE, OAK_TREE, LINDEN_TREE, ROCK, DUNE, STATION, MINE, WATER, ICE_BLOCK, METEORITE, CREVASSE, SNOWDRIFT]
## Objects that can be worked: their name, the tool ("" for bare hands) and how the tool is named in "you need a ...".
const WORK := {
	BUSH: {"name": "Krzak", "tool": "", "verb": "Wyrwij", "need": ""},
	TREE: {"name": "Drzewo", "tool": "tool_axe", "verb": "Zetnij", "need": "siekiery lub piły spalinowej"},
	SPRUCE_TREE: {"name": "Świerk", "tool": "tool_axe", "verb": "Zetnij", "need": "siekiery lub piły spalinowej"},
	BIRCH_TREE: {"name": "Brzoza", "tool": "tool_axe", "verb": "Zetnij", "need": "siekiery lub piły spalinowej"},
	OAK_TREE: {"name": "Dąb", "tool": "tool_axe", "verb": "Zetnij", "need": "siekiery lub piły spalinowej"},
	LINDEN_TREE: {"name": "Lipa", "tool": "tool_axe", "verb": "Zetnij", "need": "siekiery lub piły spalinowej"},
	MUSHROOMS: {"name": "Grzyby", "tool": "", "verb": "Zbierz", "need": ""},
	ROCK: {"name": "Skała", "tool": "tool_pickaxe", "verb": "Rozbij", "need": "kilofa"},
	DUNE: {"name": "Wydma", "tool": "tool_shovel", "verb": "Kop", "need": "łopaty"},
	WATER: {"name": "Woda", "tool": "tool_fishing_rod", "verb": "Łów", "need": "wędki"},
	FLOTSAM: {"name": "Coś wyrzuconego przez morze", "tool": "", "verb": "Zbierz", "need": ""},
	ICE_BLOCK: {"name": "Bryła lodu", "tool": "tool_pickaxe", "verb": "Rozbij", "need": "kilofa"},
	METEORITE: {"name": "Meteoryt", "tool": "tool_pickaxe", "verb": "Rozbij", "need": "kilofa"},
	SNOWDRIFT: {"name": "Zaspa", "tool": "tool_shovel", "verb": "Odkop", "need": "łopaty"},
	CREVASSE: {"name": "Szczelina", "tool": "", "verb": "Przerzuć most", "need": ""},
}
## Tools that do another's work: a saw cuts trees like an axe, only faster.
## Bronze and steel pickaxes break rock and work mines like the iron one, only faster.
const STANDS_IN := {"tool_chainsaw": "tool_axe", "tool_steel_saw": "tool_axe", "tool_harvester_saw": "tool_axe", "tool_meteorite_saw": "tool_axe", "tool_bronze_pickaxe": "tool_pickaxe", "tool_steel_pickaxe": "tool_pickaxe",
	"tool_meteorite_pickaxe": "tool_pickaxe"}
const OBJECT_NAMES := {BUSH: "Krzak", STATION: "Stacja kolejowa", MINE: "Kopalnia", WATER: "Woda", FLOTSAM: "Znalezisko",
	BRIDGE: "Most nad szczeliną"}
## What a player can put on a plot from the inventory, and its sprite there; belts are drawn by
## PlotLogistics, flat on the ground.
const PLACED_SPRITES := {
	"furniture_workbench": "workbench", "furniture_anvil": "anvil", "furniture_research_table": "research_table", "furniture_furnace": "furnace",
	"furniture_brick_furnace": "brick_furnace", "furniture_blast_furnace": "blast_furnace",
	"logistics_fast_inserter": "inserter_fast", "logistics_express_inserter": "inserter_express",
	"logistics_long_inserter": "inserter_long", "logistics_express_cable_station": "cable_station_express",
	"storage_logistics_depot": "logistics_depot", "logistics_drone_port": "drone_port",
	# Drawn by the way its opening faces, see PlotLogistics.tunnel_sprite.
	"logistics_underground_belt": "tunnel_n",
	"furniture_mill": "mill", "furniture_oil_press": "oil_press", "furniture_pickling_barrel": "pickling_barrel",
	"furniture_bakery": "bakery", "furniture_kitchen": "kitchen", "logistics_inserter": "inserter", "logistics_splitter": "splitter",
	"storage_wooden_chest": "wooden_chest", "storage_iron_chest": "iron_chest", "storage_wood_pile": "wood_pile",
	"storage_heap": "heap", "storage_grain_silo": "grain_silo", "furniture_computer": "computer",
	"power_generator": "generator", "power_pole": "pole",
	"furniture_forester_hut": "forester_hut", "furniture_forester_lodge": "forester_lodge",
	"furniture_forestry_station": "forestry_station", "furniture_sawmill": "sawmill",
	"furniture_electric_sawmill": "electric_sawmill", "furniture_industrial_sawmill": "industrial_sawmill",
	"furniture_assembler": "assembler", "furniture_fast_assembler": "fast_assembler", "furniture_express_assembler": "express_assembler",
	"furniture_drill": "drill", "furniture_heavy_drill": "heavy_drill", "furniture_quarry": "quarry",
	"furniture_crusher": "crusher", "furniture_stonemason": "stonemason", "furniture_foundry": "foundry",
	"furniture_roller_mill": "roller_mill", "furniture_flour_works": "flour_works",
	"furniture_mechanized_quarry": "mechanized_quarry", "furniture_open_pit_mine": "open_pit_mine",
	"furniture_cone_crusher": "cone_crusher", "furniture_ore_processing_plant": "ore_processing_plant",
	"power_water_wheel": "water_wheel", "power_hydro_plant": "hydro_plant", "logistics_cable_station": "cable_station",
	"furniture_fishing_boat": "fishing_boat", "furniture_rowing_boat": "rowing_boat", "furniture_smokehouse": "smokehouse",
	"furniture_cannery": "cannery", "furniture_salt_pan": "salt_pan", "furniture_fish_farm": "fish_farm",
	"furniture_shipyard": "shipyard", "furniture_port": "port", "furniture_breakwater": "breakwater",
	"furniture_lighthouse": "lighthouse", "power_tidal_plant": "tidal_plant",
	"furniture_pumpjack": "pumpjack", "furniture_gas_well": "gas_well", "furniture_offshore_platform": "offshore_platform",
	"furniture_water_injector": "water_injector", "furniture_oil_separator": "oil_separator", "furniture_distillery": "distillery",
	"furniture_refinery": "refinery", "furniture_cracker": "cracker", "furniture_chemical_plant": "chemical_plant",
	"power_gas_plant": "gas_plant", "power_diesel_generator": "diesel_generator", "logistics_pump": "pump",
	"storage_tank": "tank", "logistics_road": "road",
	"furniture_glassworks": "glassworks", "furniture_arc_furnace": "arc_furnace", "furniture_water_well": "water_well",
	"furniture_desalinator": "desalinator", "furniture_drying_yard": "drying_yard", "furniture_cement_kiln": "cement_kiln",
	"furniture_concrete_mixer": "concrete_mixer", "furniture_reed_fence": "reed_fence", "power_solar_panel": "solar_panel",
	"power_solar_tower": "solar_tower", "power_battery": "battery",
	"power_wind_turbine": "wind_turbine", "power_large_wind_turbine": "large_wind_turbine", "power_heater": "heater",
	"furniture_ice_melter": "ice_melter", "furniture_cold_store": "cold_store", "furniture_server_room": "server_room",
	"furniture_ice_core_drill": "ice_core_drill", "furniture_polar_station": "polar_station", "furniture_ice_hotel": "ice_hotel",
	"furniture_viewpoint": "viewpoint", "furniture_dog_kennel": "dog_kennel", "furniture_snowmobile_garage": "snowmobile_garage",
	"furniture_track_foundation": "track_foundation",
	"furniture_assembly_hall": "assembly_hall", "furniture_multistorey_factory": "multistorey_factory", "furniture_shop": "shop",
	"storage_high_bay": "high_bay", "furniture_city_sorter": "city_sorter", "furniture_freight_terminal": "freight_terminal",
	"furniture_company_hq": "company_hq", "furniture_design_office": "design_office", "furniture_laboratory": "laboratory",
	"furniture_service_workshop": "service_workshop", "furniture_tailor": "tailor",
	"furniture_paper_mill": "paper_mill", "furniture_carpentry": "carpentry", "furniture_charcoal_kiln": "charcoal_kiln",
	"furniture_tar_kiln": "tar_kiln", "furniture_beehive": "beehive", "furniture_fire_watchtower": "fire_watchtower",
	"furniture_fire_station": "fire_station",
	"furniture_machine_shop": "machine_shop", "furniture_robotic_hall": "robotic_hall",
	"furniture_oxygen_converter": "oxygen_converter", "furniture_rolling_mill": "rolling_mill",
	"furniture_control_center": "control_center", "furniture_continuous_caster": "continuous_caster",
	"storage_automated_warehouse": "automated_warehouse", "furniture_steel_combine": "steel_combine",
	"furniture_megafactory": "megafactory", "power_fusion_plant": "fusion_plant",
	"furniture_canteen": "canteen", "furniture_slaughterhouse": "slaughterhouse", "furniture_dairy": "dairy",
	"furniture_potato_distillery": "potato_distillery", "furniture_biogas_plant": "biogas_plant", "furniture_stable": "stable",
	"furniture_bellows": "bellows", "furniture_farmstead": "farmstead", "furniture_manor_farm": "manor_farm",
	"furniture_export_chest": "export_chest", "furniture_buy_market": "buy_market", "furniture_rail_port": "rail_port",
	"furniture_bank": "bank", "furniture_bank_branch": "bank_branch",
}
## A placed computer opens the market on the plot.
const COMPUTER := "furniture_computer"
## Animals let out on a pasture, and their sprites there.
const ANIMAL_SPRITES := {"animal_chicken": "chicken", "animal_sheep": "sheep", "animal_cow": "cow", "animal_camel": "camel",
	"animal_horse": "horse"}
## Placed objects that open the machine window.
const MACHINES := ["furniture_mill", "furniture_oil_press", "furniture_pickling_barrel", "furniture_bakery", "furniture_kitchen",
	"furniture_sawmill", "furniture_electric_sawmill", "furniture_industrial_sawmill",
	"furniture_assembler", "furniture_fast_assembler", "furniture_express_assembler",
	"furniture_quarry", "furniture_crusher", "furniture_stonemason", "furniture_foundry",
	"furniture_roller_mill", "furniture_flour_works", "furniture_mechanized_quarry", "furniture_open_pit_mine",
	"furniture_cone_crusher", "furniture_ore_processing_plant",
	"furniture_fishing_boat", "furniture_rowing_boat", "furniture_smokehouse", "furniture_cannery", "furniture_salt_pan",
	"furniture_fish_farm", "furniture_distillery", "furniture_refinery", "furniture_cracker", "furniture_chemical_plant",
	"furniture_glassworks", "furniture_arc_furnace", "furniture_water_well", "furniture_desalinator", "furniture_drying_yard",
	"furniture_cement_kiln", "furniture_concrete_mixer", "furniture_ice_melter", "furniture_cold_store", "furniture_server_room",
	"furniture_ice_core_drill", "furniture_polar_station", "furniture_ice_hotel", "furniture_viewpoint",
	"furniture_assembly_hall", "furniture_multistorey_factory", "furniture_city_sorter", "furniture_design_office",
	"furniture_laboratory", "furniture_service_workshop", "furniture_paper_mill", "furniture_carpentry", "furniture_charcoal_kiln",
	"furniture_tar_kiln", "furniture_machine_shop", "furniture_robotic_hall", "furniture_oxygen_converter", "furniture_rolling_mill",
	"furniture_continuous_caster", "furniture_steel_combine", "furniture_megafactory",
	"furniture_slaughterhouse", "furniture_dairy", "furniture_potato_distillery", "furniture_biogas_plant"]
## A works canteen opens its own window and feeds the crews of the plot's machines; a stable lets horses out on the plot,
## a bellows blows the plot's furnaces: neither opens anything.
const CANTEEN := "furniture_canteen"
const STABLE := "furniture_stable"
const BELLOWS := "furniture_bellows"
## A beehive opens its own window; a fire watchtower and a fire station only stand guard over the forest.
const BEEHIVE := "furniture_beehive"
const WATCHTOWER := "furniture_fire_watchtower"
const FIRE_STATION := "furniture_fire_station"
## Wells, which pump the oil or gas the survey found under the plot, and open the well window.
const WELLS := ["furniture_pumpjack", "furniture_gas_well", "furniture_offshore_platform"]
## Asphalt road: walked over like a belt, and faster.
const ROAD := "logistics_road"
const ROAD_SPEED := 1.5
## Drills, which stand right next to a mine (one to a mine) and work it on power.
const DRILLS := ["furniture_drill", "furniture_heavy_drill"]
## Water power, which burns nothing and stands only in the mountains, by a lake or on the coast.
const HYDRO := ["power_water_wheel", "power_hydro_plant", "power_tidal_plant"]
const TIDAL := "power_tidal_plant"
## What stands on the shore, right next to the water, and on which biome's (-1 for the sea or a lake).
const SHORE := {"furniture_fishing_boat": 10, "furniture_rowing_boat": 11, "furniture_salt_pan": 10, "power_tidal_plant": 10,
	"furniture_fish_farm": -1, "furniture_shipyard": -1, "furniture_port": -1, "furniture_breakwater": -1,
	"furniture_offshore_platform": 10, "furniture_desalinator": 10, "furniture_rail_port": 10}
const LIGHTHOUSE := "furniture_lighthouse"
const SHIPYARD := "furniture_shipyard"
const PORT := "furniture_port"
const BREAKWATER := "furniture_breakwater"
const BOATS := ["furniture_fishing_boat", "furniture_rowing_boat"]
const COAST := 10
const LAKESHORE := 11
## Quarries of every level, which stand in the mountains only.
const QUARRIES := ["furniture_quarry", "furniture_mechanized_quarry", "furniture_open_pit_mine"]
const CABLE_STATION := "logistics_cable_station"
## Cable stations of both levels, and how far their cable reaches.
const CABLE_STATIONS := {CABLE_STATION: 24, "logistics_express_cable_station": 48}
const UNDERGROUND := "logistics_underground_belt"
const DRONE_PORT := "logistics_drone_port"
## Biomes with water to turn a wheel: mountains, coast and lakeshore.
const WATER_BIOMES := [6, 10, 11]
const MOUNTAINS := 6
## The desert and its oases: the sun shines brighter there, sandstorms blow and palms grow in an oasis.
const DESERT := 5
const OASIS := 12
const SANDY := [DESERT, OASIS]
const PALMS := ["palm_0", "palm_1"]
## Solar power, which burns nothing and gives power by day; the tower with mirrors stands on 3 × 3 tiles of sand only.
const SOLAR := ["power_solar_panel", "power_solar_tower"]
const SOLAR_TOWER := "power_solar_tower"
const BATTERY := "power_battery"
const REED_FENCE := "furniture_reed_fence"
## The glacier and the tundra: wind blows stronger, blizzards sweep the glacier and the aurora shines on some nights.
const TUNDRA := 7
const GLACIER := 8
const POLAR := [TUNDRA, GLACIER]
## Wind power, which burns nothing; the large turbine stands on 3 × 3 tiles. A heater burns fuel to warm machines in the frost.
const WIND := ["power_wind_turbine", "power_large_wind_turbine"]
const LARGE_WIND := "power_large_wind_turbine"
const HEATER := "power_heater"
## What stands only on the glacier, and what on the glacier or the tundra.
const GLACIER_ONLY := ["furniture_ice_core_drill", "furniture_track_foundation"]
const POLAR_ONLY := ["furniture_ice_hotel", "furniture_viewpoint", "furniture_dog_kennel", "furniture_snowmobile_garage"]
const ICE_HOTEL := "furniture_ice_hotel"
const TRACK_FOUNDATION := "furniture_track_foundation"
## Tourist buildings, which earn more while the aurora shines.
const TOURISM := ["furniture_ice_hotel", "furniture_viewpoint"]
## Cities: only the ground by the station is built on (CITY_HALF_WIDTH tiles either side of its middle, the first CITY_ROWS rows),
## and some buildings stand only there; a freight terminal and headquarters once a plot.
const CITY := 9
const CITY_HALF_WIDTH := 30
const CITY_ROWS := 60
const CITY_ONLY := ["furniture_multistorey_factory", "furniture_shop", "storage_high_bay", "furniture_freight_terminal",
	"furniture_company_hq", "furniture_design_office", "furniture_laboratory", "furniture_service_workshop", "furniture_tailor", BUY_MARKET,
	BANK, BANK_BRANCH]
## Makes every machine on power on the plot 20% faster; opens nothing.
const CONTROL_CENTER := "furniture_control_center"
const ONE_PER_PLOT := ["furniture_freight_terminal", "furniture_company_hq", CONTROL_CENTER, CANTEEN, STABLE, BELLOWS, EXPORT_CHEST, RAIL_PORT,
	BANK, BANK_BRANCH]
## Export by rail: a chest by the station (at most EXPORT_REACH tiles from it) whose priced goods a train takes every hour to the
## nearest buying market, which stands in a town (one a town, on 3 × 3 tiles) and lists them on the players' market; across the
## sea the train goes on a ferry from a rail port on the coast. The market and the port open a window to set their commission or fee.
const EXPORT_CHEST := "furniture_export_chest"
const BUY_MARKET := "furniture_buy_market"
const RAIL_PORT := "furniture_rail_port"
## A company's bank in a town (5 × 5) and its branches in other towns (3 × 3); clicking one opens the bank's page.
const BANK := "furniture_bank"
const BANK_BRANCH := "furniture_bank_branch"
const EXPORT_REACH := 3
const ASSEMBLY_HALL := "furniture_assembly_hall"
const SHOP := "furniture_shop"
## Forester's buildings of every level and how far their forest reaches from the building's tile;
## each covers 3 × 3 tiles (FOOTPRINT each way) and keeps a clearing FOREST_CLEARING tiles out.
const FORESTERS := {"furniture_forester_hut": 5, "furniture_forester_lodge": 6, "furniture_forestry_station": 7}
const FOOTPRINT := 1
## Farmer's buildings of both levels and how far their fields reach, like the foresters'; they stand on fertile land only
## (farmland, oasis) and keep the same clearing and path free.
const FARMSTEADS := {"furniture_farmstead": 4, "furniture_manor_farm": 5}
const FERTILE := [3, 12]
const FOREST_CLEARING := 2
## How often (ms) the foresters are asked for, to draw the trees they plant and cut.
const FORESTRY_POLL := 3000.0
const BELT := "logistics_belt"
const INSERTER := "logistics_inserter"
const SPLITTER := "logistics_splitter"
## Belts and inserters of every level: plain, fast and express.
## Pipes and pumps are the belts and inserters of fluids, and go with them.
const BELTS := [BELT, "logistics_fast_belt", "logistics_express_belt", "logistics_pipe"]
const INSERTERS := [INSERTER, "logistics_fast_inserter", "logistics_express_inserter", "logistics_long_inserter", "logistics_pump"]
## Furnaces of every level, which open the furnace window.
const FURNACES := ["furniture_furnace", "furniture_brick_furnace", "furniture_blast_furnace"]
## Belts, inserters and splitters: turned with R and laid one after another.
const MACHINERY := [BELT, "logistics_fast_belt", "logistics_express_belt", INSERTER, "logistics_fast_inserter",
	"logistics_express_inserter", "logistics_long_inserter", SPLITTER, UNDERGROUND, CABLE_STATION, "logistics_express_cable_station",
	"logistics_pipe", "logistics_pump"]
const GENERATOR := "power_generator"
## Generators that burn fuel, which open the generator window.
const GENERATORS := [GENERATOR, "power_gas_plant", "power_diesel_generator", "power_fusion_plant"]
## Placed objects with nothing to open: a click shows the menu to pick them up.
const MENU_ONLY := ["power_pole", "furniture_port", "furniture_lighthouse", "furniture_breakwater", ROAD, REED_FENCE,
	"furniture_water_injector", "furniture_oil_separator", "furniture_dog_kennel", "furniture_snowmobile_garage", TRACK_FOUNDATION,
	"furniture_freight_terminal", "furniture_company_hq", WATCHTOWER, FIRE_STATION, CONTROL_CENTER]
const POLE := "power_pole"
const STORAGES := ["storage_wooden_chest", "storage_iron_chest", "storage_wood_pile", "storage_heap", "storage_grain_silo", "storage_tank",
	"storage_high_bay", "storage_automated_warehouse", "storage_logistics_depot", DRONE_PORT]
## Where a rotation faces, as players read it: 0 south, 1 east, 2 north, 3 west.
const DIRECTIONS := ["na południe", "na wschód", "na północ", "na zachód"]
const DIRECTION_ARROWS := ["↓", "→", "↑", "←"]
## How often (ms) the belts and inserters are asked for while the plot has any.
const LOGISTICS_POLL := 1000.0
## How often (ms) the station is asked for, to draw trains coming and going.
const STATION_POLL := 4000.0
## How often (ms) the player says where they stand and sees the others on the plot.
const PRESENCE_POLL := 150.0
## How often (ms) a player alone on the plot says where they stand.
const PRESENCE_POLL_ALONE := 1000.0
## Crops in the order of the art; the server sends their names and growing times.
const CROPS := ["wheat", "carrot", "cabbage", "corn", "potato", "sunflower"]
## A crop shows as a sprout until this much of its growing time is left, then half grown.
const SPROUT_UNTIL := 0.6
## Fertiliser sown with a crop makes it ripen this many times as fast; the crop menu numbers those choices from FERTILIZED.
const FERTILIZER := "fertilizer"
const FERTILIZER_SPEED := 2.0
## Manure from the animals: a crop sown on it ripens a quarter sooner (in 3/4 of the time).
const MANURE := "manure"
const MANURE_SPEED := 4.0 / 3.0
const FERTILIZED := 100
const MANURED := 200
## A planted tree shows as a sapling until this much of its growing time is left, then young;
## grown, it looks like one of the conifers of the forest.
const SAPLING_UNTIL := 0.5
const GROWN_TREES := ["tree_0", "tree_1", "tree_2"]
## Ground texture by biome id (see WorldData).
const FLOORS := {
	2: "forest", 3: "dry_grass", 4: "grass", 5: "sand", 6: "gravel", 7: "tundra",
	8: "snow", 9: "concrete", 10: "dry_grass", 11: "grass", 12: "sand",
}
const MINIMAP_COLORS := {
	NONE: Color(0, 0, 0, 0), TREE: Color("#2f5a2a"), ROCK: Color("#8a8580"), DUNE: Color("#c9a25a"),
	RAIL: Color("#4a3a2e"), STATION: Color("#b5663a"), BUSH: Color("#3f6a30"), MINE: Color("#e0b040"),
	WATER: Color("#2f6f9a"), FLOTSAM: Color("#e8d8a8"), ICE_BLOCK: Color("#9cc4dc"), METEORITE: Color("#3a2a22"),
	CREVASSE: Color("#16324a"), BRIDGE: Color("#7a5532"), SNOWDRIFT: Color("#e4e8ee"),
	SPRUCE_TREE: Color("#1f4a2a"), BIRCH_TREE: Color("#5a7a3a"), OAK_TREE: Color("#3a5a22"), LINDEN_TREE: Color("#4f6a2a"),
	MUSHROOMS: Color("#a0603a"),
}
const FIELD_COLOR := Color("#6a4526")

var _layout := {}
var _plot := {}
var _at := Vector2i(-1, -1)
var _size := 250
var _tiles := PackedByteArray()
var _harvest_seconds := 1.5
var _chop_seconds := 5.0
var _saw_seconds := 1.5
## Seconds of work on the tile being worked.
var _work_seconds := 1.5
var _world_width := 6933
var _biome_names := {}
var _my_plots: Array[Vector2i] = []
var _balance := 0
var _items: Array = []
var _ready_to_play := false
## Tilled tiles: Vector2i → { crop, readyAt } (crop and readyAt null on an empty field).
var _fields := {}
var _crops := {}
var _fertile := false
## Planted trees: Vector2i → readyAt (server milliseconds), and their kinds (the server's ids) where not a pine.
var _trees := {}
var _tree_species := {}
## The kinds of tree by sapling: { id, growSeconds, ... } as the server sends them.
var _tree_kinds := {}
## The sapling planting puts in, and how many of each kind the inventory holds.
var _planting_sapling := "sapling"
var _sapling_counts := {}
## Trees planted by hand that the bark beetle is in today.
var _infested := {}
## How long a sapling grows on this plot; 0 when nothing can be planted here.
var _tree_grow_seconds := 0.0
## Saplings in the inventory, and whether a click on free ground plants one.
var _saplings := 0
## Animals on this plot by cell: { kind, name, readyAt } (readyAt null while hungry); what kinds
## the server sends for this biome; what they eat, and how much per meal.
var _animals := {}
var _animal_kinds := {}
var _feed := []
var _feed_per_meal := 2
var _pasture := false
## The animal being let out from the inventory: a click on free ground puts it there; "" for none.
var _releasing := ""
var _planting := false
var _plant_button: Button
var _plant_count: Label
## Shown while the player stands at a mine: opens the window where it is built up.
var _mine_button: Button
var _mine_window: GameWindow
var _mine_box: VBoxContainer
## The mine whose window is open, or -1.
var _mine_open := -1
## Which crop or tree sprite each drawn field or planted tree shows, to swap it when it grows.
var _stages := {}
var _next_stage_check := 0.0
## Mines of this plot by id: { x, y, width, height, units, refillAt, level, capacity, seconds,
## refillSeconds, upgrade, sprite }; `upgrade` is the next level and its cost, or null.
var _mines := {}
var _mine_seconds := 5.0
var _mine_units := 50
## The mine under the mouse and the one being worked, or -1.
var _hover_mine := -1
var _work_mine := -1
## Objects put on the plot: tile → { id, kind, name }.
var _placed := {}
## The kind being put on the plot from the inventory, or "".
var _placing := ""
## The placed object whose window is open, or (-1, -1).
var _using := Vector2i(-1, -1)
## Which way the next belt or inserter will face (see DIRECTIONS).
var _place_rotation := 1
var _logistics: PlotLogistics
var _power: PlotPower
var _next_logistics_poll := 0.0
var _polling_logistics := false
## The plot's foresters by id, as the server last sent them.
var _foresters := {}
## The plot's farmsteads by id, as the server last told, and the fields they sow (cell → true).
var _farmsteads := {}
var _farm_fields := {}
var _next_farm_poll := 0.0
var _polling_farms := false
var _next_forestry_poll := 0.0
var _polling_forestry := false

var _astar := AStarGrid2D.new()
var _sources := {}
var _images := {}
## Sprites drawn bigger than in their files (see Footprints.GROWN), and the anchors of those and of other sprites drawn off their tile's middle.
var _grown_textures := {}
var _grown_anchors := {}
var _chunks := {}
var _player_chunk := Vector2i(-99, -99)

var _ground: Node2D
var _field_layer: TileMapLayer
var _field_source := 0
## The sea or the lake, flat on the ground under everything.
var _water_layer: TileMapLayer
var _water_source := 0
var _road_source := 0
var _crevasse_source := 0
var _bridge_source := 0
## Snow blown across the screen in a blizzard.
var _snow: CPUParticles2D
## The blizzard and the aurora last seen, to notice when they begin and end.
var _was_blizzard := false
var _shadows: TileMapLayer
var _marks: Node2D
var _sorted: Node2D
var _objects: TileMapLayer
var _station: Sprite2D
var _player: GaragePlayer
var _camera := Camera2D.new()
var _zoom := 1.0
## Fingers on the screen, by index, and their distance at the last step of a pinch.
var _touches := {}
var _pinch := 0.0

var _path: PackedVector2Array = []
var _on_arrival := Callable()
var _hovered := Vector2i(-1, -1)
## Objects in front of the player, drawn see-through so the character never gets lost.
var _faded := {}
var _hover_station := false
## The object being held to put it away (its id, the button holding it and where the finger started), and how long so far.
var _hold_id := ""
var _hold_button := MOUSE_BUTTON_NONE
var _hold_from := Vector2.ZERO
var _hold_for := 0.0
## The tile being worked, and seconds of work left.
var _work := Vector2i(-1, -1)
var _work_left := 0.0
## "harvest" for trees, rocks and dunes, "till" for the hoe, "mine" for a mine.
var _work_mode := "harvest"

var _hud: Control
var _title: Label
var _subtitle: Label
## The sea forecast on the coast and the lakeshore: the storm blowing now or the next one.
var _weather: Label
var _next_weather := 0.0
## Tints the plot by the sun: dim and blue at night, yellow in a sandstorm.
var _daylight := CanvasModulate.new()
var _daylight_target := Color.WHITE
var _level: Label
var _xp_bar: ProgressBar
var _money: Label
var _tool_slot: ToolSlot
var _hint: Label
var _prompt: Label
var _field_label: Label
var _crop_menu: PopupMenu
## Turn or pick up a belt or inserter.
var _object_menu: PopupMenu
var _menu_object := Vector2i(-1, -1)
var _menu_cell := Vector2i(-1, -1)
## Feed, milk, shear or take an animal.
var _animal_menu: PopupMenu
var _menu_animal := Vector2i(-1, -1)
var _work_bar: ProgressBar
var _toast: Label
var _toast_tween: Tween
var _minimap: TextureRect
var _minimap_image: Image
var _minimap_dot: Control
var _loading: Label

var _inventory_window: GameWindow
var _slots: InventoryGrid
var _station_window: StationWindow
## Trains on the track, drawn from what the station knows.
var _trains: PlotTrains
## The other players on the plot.
var _others: PlotPlayers
var _next_presence_poll := 0.0
var _polling_presence := false
var _crafting_window: CraftingWindow
var _research_window: ResearchWindow
var _furnace_window: FurnaceWindow
var _storage_window: StorageWindow
var _splitter_window: SplitterWindow
var _filter_window: FilterWindow
## Small icons of the filtered item on every object with a filter, over everything standing on the plot.
var _filter_marks: Node2D
var _company_window: CompanyWindow
var _stats_window: StatsWindow
var _machine_window: MachineWindow
var _forester_window: ForesterWindow
var _farmstead_window: FarmsteadWindow
var _canteen_window: CanteenWindow
var _market_window: MarketWindow
## "Rynek [M]" in the bar: shown while a computer stands on the plot.
var _market_button: Button
var _generator_window: GeneratorWindow
var _drill_window: DrillWindow
var _well_window: WellWindow
var _shop_window: ShopWindow
var _export_window: ExportWindow
var _export_post_window: ExportPostWindow
var _bank_window: BankWindow
var _hive_window: HiveWindow
var _city_window: CityWindow
var _city_button: Button
var _achievements_window: AchievementsWindow
var _character_window: CharacterWindow
var _clock_offset := 0.0
var _next_station_poll := 0.0


func _ready() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: Key in ACTIONS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)
	RenderingServer.set_default_clear_color(Color("#08090a"))
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
	_build_world()
	_build_hud()
	_build_windows()
	_load()


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(UI.BACKGROUND)
	# The others stop seeing the player at once instead of after the server's timeout.
	if _ready_to_play and Net.is_open():
		Net.send("plot.leave")


# --- World ---------------------------------------------------------------------------

func _build_world() -> void:
	_ground = Node2D.new()
	add_child(_ground)
	add_child(_daylight)
	_water_layer = TileMapLayer.new()
	var water_set := TileSet.new()
	water_set.tile_size = Vector2i(TILE)
	_water_source = _add_source(water_set, "water", "water", false)
	_water_layer.tile_set = water_set
	add_child(_water_layer)
	# Tilled fields lie flat on the ground, under every shadow.
	_field_layer = TileMapLayer.new()
	var field_set := TileSet.new()
	field_set.tile_size = Vector2i(TILE)
	_field_source = _add_source(field_set, "field", "field", false)
	# So are asphalt roads.
	_road_source = _add_source(field_set, "road", "road", false)
	# And crevasses in the glacier, with the bridges laid over them.
	_crevasse_source = _add_source(field_set, "crevasse", "crevasse", false)
	_bridge_source = _add_source(field_set, "bridge", "bridge", false)
	_field_layer.tile_set = field_set
	add_child(_field_layer)
	_shadows = TileMapLayer.new()
	_shadows.tile_set = _tile_set(true)
	add_child(_shadows)
	# Belts lie on the ground under everything standing; inserter arms stand among the rest.
	_logistics = PlotLogistics.new()
	_logistics.tile = TILE
	_logistics.layout = _layout
	_logistics.server_now = _server_now
	add_child(_logistics)
	# Rings on the ground under the object the mouse points at.
	_marks = Node2D.new()
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	add_child(_sorted)
	_objects = TileMapLayer.new()
	_objects.y_sort_enabled = true
	_objects.tile_set = _tile_set(false)
	_sorted.add_child(_objects)
	_trains = PlotTrains.new()
	_trains.layout = _layout
	_trains.server_now = _server_now
	_sorted.add_child(_trains)
	_logistics.arms_parent = _sorted
	# Wires hang over everything standing on the plot.
	_power = PlotPower.new()
	_power.tile = TILE
	_power.layout = _layout

	_player = GaragePlayer.new(Game.look(), Game.appearance_options)
	_player.light = LIGHT
	_player.scale = Vector2.ONE * PLAYER_SCALE
	_player.shadow.scale = Vector2.ONE * PLAYER_SCALE
	_player.visible = false
	_player.shadow.visible = false
	add_child(_player.shadow)
	move_child(_player.shadow, _marks.get_index())
	_sorted.add_child(_player)
	_others = PlotPlayers.new()
	_others.tile = TILE
	_others.player_scale = PLAYER_SCALE
	_others.light = LIGHT
	_others.shadows_parent = Node2D.new()
	add_child(_others.shadows_parent)
	move_child(_others.shadows_parent, _marks.get_index())
	_sorted.add_child(_others)

	add_child(_power)
	_filter_marks = Node2D.new()
	_filter_marks.draw.connect(_draw_filters)
	add_child(_filter_marks)
	_logistics.filters_changed.connect(_on_filters_changed)

	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)
	_snow = CPUParticles2D.new()
	_snow.emitting = false
	_snow.amount = 500
	_snow.lifetime = 2.5
	_snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_snow.emission_rect_extents = Vector2(1100, 50)
	_snow.position = Vector2(200, -650)
	_snow.direction = Vector2(-0.6, 1)
	_snow.spread = 12.0
	_snow.gravity = Vector2(-120, 260)
	_snow.initial_velocity_min = 260.0
	_snow.initial_velocity_max = 420.0
	_snow.scale_amount_min = 1.5
	_snow.scale_amount_max = 3.5
	_snow.color = Color(1, 1, 1, 0.8)
	_snow.z_index = 100
	_camera.add_child(_snow)


## One atlas source per sprite, so every sprite keeps its own size and anchor; an alternative
## tile of each object is brightened for the mouse.
func _tile_set(shadows: bool) -> TileSet:
	var set := TileSet.new()
	set.tile_size = Vector2i(TILE)
	var sprites: Array[String] = []
	for kind: int in SPRITES:
		sprites.append_array(SPRITES[kind])
	sprites.append_array(["sapling", "tree_young"])
	sprites.append_array(PALMS)
	sprites.append_array(ANIMAL_SPRITES.values())
	sprites.append_array(PLACED_SPRITES.values())
	sprites.append_array(PlotLogistics.TUNNEL_SPRITES.filter(func(t: String) -> bool: return t != PLACED_SPRITES[UNDERGROUND]))
	for sprite in sprites:
		_add_source(set, sprite, sprite + ("_shadow" if shadows else ""), not shadows)
	if not shadows:
		# Crops have no shadows of their own; their ids come after those of nature in both sets.
		sprites = ["sprout"]
		for crop: String in CROPS:
			sprites.append_array([crop + "_young", crop + "_ripe"])
		for sprite in sprites:
			_add_source(set, sprite, sprite, true)
	return set


## Adds one sprite as a tile anchored on the cell's centre; with `looks`, also a brightened
## (alternative 1) and a see-through (alternative 2) version. Returns the source id.
## A grown machine's sprite is enlarged to its square and stands in the square's middle.
func _add_source(set: TileSet, sprite: String, file: String, looks: bool) -> int:
	var texture: Texture2D = load("res://art/plot/%s.png" % file)
	var anchor := Vector2(_layout[sprite]["anchorX"], _layout[sprite]["anchorY"])
	var kind := _placed_kind(sprite)
	if Footprints.GROWN.has(kind):
		var scale := Footprints.sprite_scale(kind, Vector2(_layout_size(sprite)), TILE)
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		image.resize(roundi(image.get_width() * scale), roundi(image.get_height() * scale), Image.INTERPOLATE_CUBIC)
		texture = ImageTexture.create_from_image(image)
		anchor *= scale
		if looks:
			_grown_textures[sprite] = texture
	if Footprints.shift(kind) != Vector2.ZERO:
		# An even square's middle lies on the corner of its tiles, half a tile right of and below the object's own tile.
		anchor -= Footprints.shift(kind) * TILE
	if looks and anchor != Vector2(_layout[sprite]["anchorX"], _layout[sprite]["anchorY"]):
		_grown_anchors[sprite] = anchor
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(texture.get_size())
	source.create_tile(Vector2i.ZERO)
	var origin := Vector2i(anchor.round()) - Vector2i(texture.get_size() / 2)
	source.get_tile_data(Vector2i.ZERO, 0).texture_origin = origin
	if looks:
		for modulate: Color in [Color(1.45, 1.4, 1.25), Color(1, 1, 1, 0.4)]:
			var alternative := source.create_alternative_tile(Vector2i.ZERO)
			var data := source.get_tile_data(Vector2i.ZERO, alternative)
			data.texture_origin = origin
			data.modulate = modulate
	var id := set.add_source(source)
	if looks:
		_sources[sprite] = id
		_images[sprite] = texture.get_image()
	return id


## The kind of placed object a sprite stands for, or "" for nature and the like.
func _placed_kind(sprite: String) -> String:
	var kind: Variant = PLACED_SPRITES.find_key(sprite)
	return kind if kind != null else ""


## The size of a sprite's own picture (its shadow may be bigger), which a grown machine's sprite is enlarged by.
func _layout_size(sprite: String) -> Vector2i:
	var texture: Texture2D = load("res://art/plot/%s.png" % sprite)
	return Vector2i(texture.get_size())


## Where a sprite's anchor lies in its picture as drawn: on the cell's centre.
func _sprite_anchor(sprite: String) -> Vector2:
	return _grown_anchors.get(sprite, Vector2(_layout[sprite]["anchorX"], _layout[sprite]["anchorY"]))


func _apply_plot(plot: Dictionary) -> void:
	_plot = plot
	_size = plot["size"]
	_harvest_seconds = plot["harvestSeconds"]
	_chop_seconds = plot.get("chopSeconds", _harvest_seconds)
	_saw_seconds = plot.get("sawSeconds", _chop_seconds)
	_mine_seconds = plot.get("mineSeconds", _chop_seconds)
	_mine_units = plot.get("mineUnits", _mine_units)
	var grow: Variant = plot.get("treeGrowSeconds")
	_tree_grow_seconds = float(grow) if grow != null else 0.0
	var packed := Marshalls.base64_to_raw(plot["tiles"])
	_tiles = packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	_sync_tool_bar()
	_fertile = plot.get("fertile", false)
	for crop: Dictionary in plot.get("crops", []):
		_crops[crop["id"]] = crop
	_pasture = plot.get("pasture", false)
	for kind: Dictionary in plot.get("animalKinds", []):
		_animal_kinds[kind["id"]] = kind
	_feed = plot.get("feed", [])
	_feed_per_meal = int(plot.get("feedPerMeal", 2))
	for animal: Dictionary in plot.get("animals", []):
		_animals[Vector2i(animal["tileX"], animal["tileY"])] = animal
	_clock_offset = float(plot["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	for field: Dictionary in plot.get("fields", []):
		_fields[Vector2i(field["tileX"], field["tileY"])] = {"crop": field["crop"], "readyAt": field["readyAt"]}
	for tree: Dictionary in plot.get("trees", []):
		_trees[Vector2i(tree["tileX"], tree["tileY"])] = tree["readyAt"]
		_tree_species[Vector2i(tree["tileX"], tree["tileY"])] = tree.get("species", "pine")
	for kind: Dictionary in plot.get("treeKinds", []):
		_tree_kinds[kind["sapling"]] = kind
	_apply_pests(plot.get("pests", {}))
	for object: Dictionary in plot.get("objects", []):
		_put_placed(object)
	_logistics.set_objects(_placed)
	_draw_tunnels()
	_power.set_objects(_placed)

	# The ground: the biome's texture repeated over the plot, squashed to the 45° view.
	var floor_name: String = FLOORS.get(int(plot["biome"]), "grass")
	var ground := Sprite2D.new()
	ground.texture = load("res://art/plot/floor_%s.png" % floor_name)
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.centered = false
	ground.region_enabled = true
	var squash := TILE.y / TILE.x
	ground.region_rect = Rect2(0, 0, _size * TILE.x, _size * TILE.y / squash)
	ground.scale = Vector2(1, squash)
	_ground.add_child(ground)
	# A dark band around the edge of the plot.
	var edge := Line2D.new()
	edge.points = PackedVector2Array([Vector2.ZERO, Vector2(_size * TILE.x, 0), _size * TILE, Vector2(0, _size * TILE.y), Vector2.ZERO])
	edge.width = 6
	edge.default_color = Color(0.9, 0.7, 0.3, 0.35)
	_ground.add_child(edge)
	if int(plot["biome"]) == CITY:
		# In a city only the ground by the station is built on.
		var mid := int(plot["spawn"]["x"])
		var area := Rect2(Vector2((mid - CITY_HALF_WIDTH) * TILE.x, 0), Vector2((CITY_HALF_WIDTH * 2 + 1) * TILE.x, CITY_ROWS * TILE.y))
		var fence := Line2D.new()
		fence.points = PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end,
			Vector2(area.position.x, area.end.y), area.position])
		fence.width = 3
		fence.default_color = Color(0.85, 0.85, 0.9, 0.4)
		_ground.add_child(fence)

	# The railway across the plot.
	var rail := Sprite2D.new()
	rail.texture = load("res://art/plot/rail.png")
	rail.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rail.region_enabled = true
	rail.centered = false
	var rail_height: float = rail.texture.get_height()
	rail.region_rect = Rect2(0, 0, _size * TILE.x + 512, rail_height)
	rail.position = Vector2(-256, (int(plot["railRow"]) + 0.5) * TILE.y - float(_layout["rail"]["anchorY"]))
	_ground.add_child(rail)

	# The station stands on its tiles with the middle of its south edge as anchor.
	var s: Dictionary = plot["station"]
	var foot := Vector2((int(s["x"]) + int(s["width"]) / 2.0) * TILE.x, (int(s["y"]) + int(s["height"])) * TILE.y)
	var station_anchor := Vector2(_layout["station"]["anchorX"], _layout["station"]["anchorY"])
	_station = Sprite2D.new()
	_station.texture = load("res://art/plot/station.png")
	_station.centered = false
	_station.offset = -station_anchor
	_station.position = foot
	_sorted.add_child(_station)
	_images["station"] = _station.texture.get_image()
	var station_shadow := Sprite2D.new()
	station_shadow.texture = load("res://art/plot/station_shadow.png")
	station_shadow.centered = false
	station_shadow.offset = -station_anchor
	station_shadow.position = foot
	_shadows.add_child(station_shadow)
	_trains.shadows_parent = _shadows
	_trains.stop = Vector2(foot.x, (int(plot["railRow"]) + 0.5) * TILE.y)
	for mine: Dictionary in plot.get("mines", []):
		_add_mine(mine)

	_build_paths()
	_build_minimap()
	_camera.limit_left = -200
	_camera.limit_top = -320
	_camera.limit_right = int(_size * TILE.x) + 200
	_camera.limit_bottom = int(_size * TILE.y) + 200

	var spawn := Vector2(plot["spawn"]["x"], plot["spawn"]["y"]) + Vector2(0.5, 0.5)
	_player.visible = true
	_player.shadow.visible = true
	_place_player(spawn)
	_player.face(Vector2(0, -1))
	_others.plot_size = _size
	_camera.position = _player.position
	_camera.reset_smoothing()
	_update_chunks(true)
	_ready_to_play = true


func _tile(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= _size or cell.y >= _size:
		return -1
	return _tiles[cell.y * _size + cell.x]


func _variant(kind: int, cell: Vector2i) -> String:
	var options: Array = PALMS if kind == TREE and _sandy() else SPRITES[kind]
	var h := (cell.x * 73856093) ^ (cell.y * 19349663)
	return options[absi(h) % options.size()]


## Whether the plot lies on the sand of a desert or an oasis.
func _sandy() -> bool:
	return int(_plot.get("biome", -1)) in SANDY


## Whether an object of `kind` stands on more than one tile (see Footprints).
func _big(kind: String) -> bool:
	return Footprints.size(kind) > 1


## The middle of the square an object of `kind` standing on `cell` covers, on the ground.
func _object_centre(kind: String, cell: Vector2i) -> Vector2:
	return _cell_centre(cell) + Footprints.shift(kind) * TILE


## How big a ring around an object of `kind` is: one tile's for a small one, its square's for a big one.
func _ring_size(kind: String) -> float:
	return 1.0 + 0.7 * (Footprints.size(kind) - 1)


## Whether a tile of a city plot can be built on: by the station only.
func _in_city_area(cell: Vector2i) -> bool:
	var spawn: Dictionary = _plot.get("spawn", {})
	return absi(cell.x - int(spawn.get("x", 125))) <= CITY_HALF_WIDTH and cell.y < CITY_ROWS


func _biome() -> int:
	return int(_plot.get("biome", -1))


func _cell_centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


## Draws the chunks near the player and forgets the far ones.
func _update_chunks(force := false) -> void:
	var here := Vector2i((_player.floor_pos / CHUNK).floor())
	if here == _player_chunk and not force:
		return
	_player_chunk = here
	for chunk: Vector2i in _chunks.keys():
		if absi(chunk.x - here.x) > CHUNK_RADIUS + 1 or absi(chunk.y - here.y) > CHUNK_RADIUS + 1:
			_chunks.erase(chunk)
			for y in CHUNK:
				for x in CHUNK:
					var cell := chunk * CHUNK + Vector2i(x, y)
					_objects.erase_cell(cell)
					_shadows.erase_cell(cell)
					_field_layer.erase_cell(cell)
					_water_layer.erase_cell(cell)
					_stages.erase(cell)
	for cy in range(here.y - CHUNK_RADIUS, here.y + CHUNK_RADIUS + 1):
		for cx in range(here.x - CHUNK_RADIUS, here.x + CHUNK_RADIUS + 1):
			var chunk := Vector2i(cx, cy)
			if _chunks.has(chunk) or cx < 0 or cy < 0 or cx * CHUNK >= _size or cy * CHUNK >= _size:
				continue
			_chunks[chunk] = true
			for y in CHUNK:
				for x in CHUNK:
					_draw_cell(chunk * CHUNK + Vector2i(x, y))


## Redraws the underground belts on the tiles drawn now: placing or picking one up may pair others anew.
func _draw_tunnels() -> void:
	for cell: Vector2i in _placed:
		if _placed[cell]["kind"] == UNDERGROUND and _chunks.has(Vector2i((Vector2(cell) / CHUNK).floor())):
			_draw_cell(cell)


func _draw_cell(cell: Vector2i) -> void:
	if _tile(cell) == WATER:
		_water_layer.set_cell(cell, _water_source, Vector2i.ZERO)
	if _fields.has(cell):
		_field_layer.set_cell(cell, _field_source, Vector2i.ZERO)
	elif _placed.has(cell) and _placed[cell]["kind"] == ROAD:
		_field_layer.set_cell(cell, _road_source, Vector2i.ZERO)
	elif _tile(cell) == CREVASSE:
		_field_layer.set_cell(cell, _crevasse_source, Vector2i.ZERO)
	elif _tile(cell) == BRIDGE:
		_field_layer.set_cell(cell, _bridge_source, Vector2i.ZERO)
	else:
		_field_layer.erase_cell(cell)
	var sprite := _sprite_at(cell)
	if sprite == "":
		_objects.erase_cell(cell)
		_shadows.erase_cell(cell)
		_stages.erase(cell)
		return
	var id: int = _sources[sprite]
	var look := 1 if cell == _hovered else (2 if _faded.has(cell) else 0)
	_objects.set_cell(cell, id, Vector2i.ZERO, look)
	if _fields.has(cell) or _trees.has(cell):
		_stages[cell] = sprite
	if _fields.has(cell):
		_shadows.erase_cell(cell)
	else:
		_shadows.set_cell(cell, id, Vector2i.ZERO)


## The sprite standing on a tile: nature, the crop growing on a field, a planted tree or an animal; "" for nothing.
func _sprite_at(cell: Vector2i) -> String:
	if _tile(cell) == SNOWDRIFT:
		return _variant(SNOWDRIFT, cell)  # over whatever the avalanche buried, too
	if _placed.has(cell):
		if _anchor(cell) != cell:
			return ""  # A 3 × 3 building is drawn once, on its own tile.
		if _placed[cell]["kind"] == ROAD:
			return ""  # flat on the ground, with the fields
		if _placed[cell]["kind"] == UNDERGROUND:
			return _logistics.tunnel_sprite(cell, int(_placed[cell].get("rotation", 0)))
		return PLACED_SPRITES.get(_placed[cell]["kind"], "")  # "" for a belt
	if _animals.has(cell):
		return ANIMAL_SPRITES.get(_animals[cell]["kind"], "")
	if _fields.has(cell):
		return _crop_sprite(cell)
	if _trees.has(cell):
		return _tree_sprite(cell)
	var kind := _tile(cell)
	return _variant(kind, cell) if SPRITES.has(kind) else ""


func _crop_sprite(cell: Vector2i) -> String:
	var field: Dictionary = _fields[cell]
	if field["crop"] == null:
		return ""
	var left := _crop_left(cell)
	if left <= 0.0:
		return field["crop"] + "_ripe"
	var grow: float = _crops.get(field["crop"], {}).get("growSeconds", 60.0)
	return "sprout" if left > grow * SPROUT_UNTIL else field["crop"] + "_young"


func _tree_sprite(cell: Vector2i) -> String:
	var left := _tree_left(cell)
	var species: String = _tree_species.get(cell, "pine")
	if left <= 0.0:
		var h := (cell.x * 73856093) ^ (cell.y * 19349663)
		var grown: Array = GROWN_TREES if species == "pine" else SPRITES[SPECIES_TILES.get(species, TREE)]
		return grown[absi(h) % grown.size()]
	return "sapling" if left > _grow_seconds(species) * SAPLING_UNTIL else "tree_young"


## How long a tree of a kind grows on this plot.
func _grow_seconds(species: String) -> float:
	for kind: Dictionary in _tree_kinds.values():
		if kind["id"] == species and kind.get("growSeconds") != null:
			return float(kind["growSeconds"])
	return _tree_grow_seconds


## Seconds until a planted tree can be cut (0 when it can).
func _tree_left(cell: Vector2i) -> float:
	return maxf((float(_trees[cell]) - _server_now()) / 1000.0, 0.0)


func _tree_grown(cell: Vector2i) -> bool:
	return _trees.has(cell) and _tree_left(cell) <= 0.0


## What is worked on a tile: a grown planted tree counts as a tree.
func _work_kind(cell: Vector2i) -> int:
	return int(SPECIES_TILES.get(_tree_species.get(cell, "pine"), TREE)) if _tree_grown(cell) else _tile(cell)


## Seconds until the crop on a field is ripe (0 when it is).
func _crop_left(cell: Vector2i) -> float:
	var ready_at: Variant = _fields[cell]["readyAt"]
	return maxf((float(ready_at) - _server_now()) / 1000.0, 0.0) if ready_at != null else 0.0


func _ripe(cell: Vector2i) -> bool:
	return _fields.has(cell) and _fields[cell]["crop"] != null and _crop_left(cell) <= 0.0


## Swaps the sprites of crops and trees that grew into their next stage.
func _update_stages() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_stage_check:
		return
	_next_stage_check = now + 1.0
	for cell: Vector2i in _stages.keys():
		if _sprite_at(cell) != _stages[cell]:
			_draw_cell(cell)


# --- Walking ---------------------------------------------------------------------------

func _build_paths() -> void:
	_astar.region = Rect2i(0, 0, _size, _size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in _size:
		for x in _size:
			if _tiles[y * _size + x] in SOLID:
				_astar.set_point_solid(Vector2i(x, y), true)
	for cell: Vector2i in _placed:
		_astar.set_point_solid(cell, not _walkable(cell))


func _solid(cell: Vector2i) -> bool:
	var kind := _tile(cell)
	return kind < 0 or kind in SOLID or (_placed.has(cell) and not _walkable(cell))


func _is_belt(cell: Vector2i) -> bool:
	return _placed.has(cell) and _placed[cell]["kind"] in BELTS


## Belts and roads lie flat, inserters and the low portals of underground belts are low enough to step
## over and a power pole is thin enough to slip past: the player walks across them.
func _walkable(cell: Vector2i) -> bool:
	return _is_belt(cell) or (_placed.has(cell) and (_placed[cell]["kind"] in [ROAD, POLE, UNDERGROUND] or _placed[cell]["kind"] in INSERTERS))


## How fast the player walks where they stand: faster on a road.
func _speed() -> float:
	var cell := Vector2i(_player.floor_pos.floor())
	return SPEED * ROAD_SPEED if _placed.has(cell) and _placed[cell]["kind"] == ROAD else SPEED


## Belts, inserters and splitters are turned and picked up from a menu; other placed objects open a window.
func _turnable(cell: Vector2i) -> bool:
	return _placed.has(cell) and _placed[cell]["kind"] in MACHINERY


## Whether the player can stand at a position (in tiles).
func _free(pos: Vector2) -> bool:
	for offset: Vector2 in [Vector2(-RADIUS, 0), Vector2(RADIUS, 0), Vector2(0, -RADIUS * 0.5), Vector2(0, RADIUS * 0.5)]:
		if _solid(Vector2i((pos + offset).floor())):
			return false
	return true


func _place_player(pos: Vector2) -> void:
	_player.floor_pos = pos
	_player.position = pos * TILE
	_player.shadow.position = _player.position


## Walks to a tile along a path around the trees and rocks, then calls `arrival`. When the
## tile itself is blocked (a tree to cut), the path ends next to it.
func _walk_to(cell: Vector2i, arrival := Callable(), stop_next_to := false) -> void:
	var from := Vector2i(_player.floor_pos.floor())
	var target_solid := _astar.is_point_solid(cell) if _astar.region.has_point(cell) else true
	if stop_next_to and _astar.region.has_point(cell):
		_astar.set_point_solid(cell, false)
	var cells := _astar.get_id_path(from, cell.clamp(Vector2i.ZERO, Vector2i(_size - 1, _size - 1)), true)
	if stop_next_to and _astar.region.has_point(cell):
		_astar.set_point_solid(cell, target_solid)
		if not cells.is_empty() and cells[-1] == cell:
			cells.remove_at(cells.size() - 1)
	_path = PackedVector2Array()
	for i in range(1, cells.size()):
		_path.append(Vector2(cells[i]) + Vector2(0.5, 0.5))
	_on_arrival = arrival
	if _path.is_empty():
		_arrive()


func _arrive() -> void:
	var arrival := _on_arrival
	_on_arrival = Callable()
	if arrival.is_valid():
		arrival.call()


func _move_player(delta: float) -> void:
	var step := Vector2.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _focus_in_text():
		input = Vector2.ZERO
	if input != Vector2.ZERO:
		_path = PackedVector2Array()
		_on_arrival = Callable()
		_stop_work()
		step = input * _speed() * delta
	elif not _path.is_empty():
		var to_next := _path[0] - _player.floor_pos
		var length := _speed() * delta
		if to_next.length() <= length:
			step = to_next
			_path.remove_at(0)
		else:
			step = to_next.normalized() * length
	var start := _player.floor_pos
	var pos := start
	# Slide along whatever blocks the way, one axis at a time.
	if _free(pos + Vector2(step.x, 0)):
		pos.x += step.x
	if _free(pos + Vector2(0, step.y)):
		pos.y += step.y
	_player.walking = pos.distance_to(start) > 0.0001
	if _player.walking:
		# The character's "up" is away from the camera, which is -y here.
		_player.face(Vector2(step.x, -step.y))
		_place_player(pos)
	elif not _path.is_empty():
		_path = PackedVector2Array()  # Stuck: give up instead of pushing against a tree.
	if _path.is_empty() and _on_arrival.is_valid():
		_arrive()


func _focus_in_text() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox


# --- Mouse -------------------------------------------------------------------------------

## The object drawn under a point of the world: the front-most sprite with a solid pixel there.
func _object_at(point: Vector2) -> Vector2i:
	var cells := _objects_at(point, true)
	return cells[0] if not cells.is_empty() else Vector2i(-1, -1)


## Every object drawn over a point, front-most first.
func _objects_at(point: Vector2, first_only := false) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var base := Vector2i((point / TILE).floor())
	# Big machines stand far below the top of their sprites.
	for dy in range(11, -3, -1):
		for dx in [0, -1, 1, -2, 2, -3, 3]:
			var cell := base + Vector2i(dx, dy)
			var sprite := _sprite_at(cell)
			if sprite == "":
				continue
			var image: Image = _images[sprite]
			var pixel := Vector2i(point - _cell_centre(cell) + _sprite_anchor(sprite))
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.4:
				found.append(cell)
				if first_only:
					return found
	return found


## Makes the objects standing in front of the character see-through.
func _update_fade() -> void:
	var covering := {}
	for lift in [8.0, 30.0, 52.0]:
		for cell in _objects_at(_player.position - Vector2(0, lift)):
			if _cell_centre(cell).y > _player.position.y:
				covering[cell] = true
	if covering == _faded:
		return
	var changed := _faded.keys()
	changed.append_array(covering.keys())
	_faded = covering
	for cell: Vector2i in changed:
		_draw_cell(cell)


func _station_at(point: Vector2) -> bool:
	if _station == null:
		return false
	var pixel := Vector2i(point - _station.position - _station.offset)
	var image: Image = _images["station"]
	return Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.4


func _update_hover() -> void:
	var cell := Vector2i(-1, -1)
	var station := false
	var mine := -1
	if _ready_to_play and get_viewport().gui_get_hovered_control() == null:
		var mouse := get_global_mouse_position()
		cell = _object_at(mouse)
		if cell.x < 0 and _is_belt(Vector2i((mouse / TILE).floor())):
			cell = Vector2i((mouse / TILE).floor())
		station = cell == Vector2i(-1, -1) and _station_at(mouse)
		if cell == Vector2i(-1, -1) and not station:
			mine = _mine_at(mouse)
	if cell != _hovered:
		var old := _hovered
		_hovered = cell
		if old.x >= 0:
			_draw_cell(old)
		if cell.x >= 0:
			_draw_cell(cell)
	_hover_station = station
	if station:
		_station.modulate = Color(1.2, 1.17, 1.08)
	elif _station != null:
		_station.modulate = Color.WHITE
	if mine != _hover_mine:
		if _mines.has(_hover_mine):
			_mines[_hover_mine]["sprite"].modulate = Color.WHITE
		_hover_mine = mine
		if mine >= 0:
			_mines[mine]["sprite"].modulate = Color(1.25, 1.2, 1.1)
	var ground := _ground_cell()
	var pointing := cell.x >= 0 or station or mine >= 0 or _fields.has(ground) or _can_till(ground) or _can_plant(ground) or _can_place(ground) \
		or _can_release(ground) or (_tile(ground) == WATER and _placing == "" and _releasing == "" and _holds(WORK[WATER]["tool"]))
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if pointing else Input.CURSOR_ARROW)
	_marks.queue_redraw()
	_update_prompt()
	if mine >= 0:
		_update_mine_label(mine)
	else:
		_update_field_label(cell if cell.x >= 0 and (_fields.has(cell) or _trees.has(cell) or _placed.has(cell) or _animals.has(cell)) else ground)


## The tile under the mouse, or (-1, -1) when the mouse is over the interface.
func _ground_cell() -> Vector2i:
	if not _ready_to_play or get_viewport().gui_get_hovered_control() != null:
		return Vector2i(-1, -1)
	return Vector2i((get_global_mouse_position() / TILE).floor())


## Whether the hoe can turn this tile into a field.
func _can_till(cell: Vector2i) -> bool:
	return _placing == "" and _releasing == "" and _fertile and Game.holds("tool_hoe") and _tile(cell) == NONE \
		and not _fields.has(cell) and not _placed.has(cell) and not _animals.has(cell)


## Whether a sapling can be planted on this tile now.
func _can_plant(cell: Vector2i) -> bool:
	return _planting and _tree_grow_seconds > 0.0 and _tile(cell) == NONE and not _fields.has(cell) and not _trees.has(cell) and not _placed.has(cell) \
		and not _animals.has(cell)


## Whether the animal being let out can go on this tile: free ground, not under the player.
func _can_release(cell: Vector2i) -> bool:
	var spawn: Dictionary = _plot.get("spawn", {})
	return _releasing != "" and _tile(cell) == NONE and not _fields.has(cell) and not _trees.has(cell) and not _placed.has(cell) \
		and not _animals.has(cell) and cell != Vector2i(spawn.get("x", -1), spawn.get("y", -1)) and Vector2i(_player.floor_pos.floor()) != cell


## Whether the object being placed can go on this tile: free ground, not under the player; a
## forester's building needs the 3 × 3 tiles around it free.
func _can_place(cell: Vector2i) -> bool:
	if _placing == "":
		return false
	# The player steps off a big building's ground before it goes up (_place_big), so standing there is fine.
	var big := _big(_placing)
	var city := _biome() == CITY
	for at in _footprint(_placing, cell):
		if not _free_ground(at, not big) or (city and not _in_city_area(at)):
			return false
	if _placing in CITY_ONLY and not city:
		return false
	if _placing in ONE_PER_PLOT and _count_placed(_placing) > 0:
		return false
	if _placing == EXPORT_CHEST and not _by_station(cell):
		return false
	if _placing in DRILLS:
		var mine := _mine_beside(cell)
		return mine >= 0 and _drill_at(mine).x < 0
	if _placing in QUARRIES:
		return int(_plot.get("biome", -1)) == MOUNTAINS
	var biome := int(_plot.get("biome", -1))
	if _placing == LIGHTHOUSE:
		return biome == COAST
	if SHORE.has(_placing):
		var only: int = SHORE[_placing]
		# A big one (the rail port) has the water along any edge of its ground.
		return (biome == only if only >= 0 else biome in [COAST, LAKESHORE]) and _footprint(_placing, cell).any(_by_water)
	if _placing in HYDRO:
		return biome in WATER_BIOMES
	if _placing == SOLAR_TOWER:
		return biome in SANDY
	if _placing in GLACIER_ONLY:
		if _placing == TRACK_FOUNDATION and _count_placed(TRACK_FOUNDATION) > 0:
			return false
		return biome == GLACIER
	if _placing in POLAR_ONLY:
		return biome in POLAR
	if FARMSTEADS.has(_placing):
		return biome in FERTILE
	return true


## Whether a tile is at most EXPORT_REACH tiles from the station building or the platform track in front of it.
func _by_station(cell: Vector2i) -> bool:
	var s: Dictionary = _plot.get("station", {})
	if s.is_empty():
		return false
	var left := int(s["x"]) - EXPORT_REACH
	var right := int(s["x"]) + int(s["width"]) - 1 + EXPORT_REACH
	var top := int(s["y"]) - EXPORT_REACH
	var bottom := maxi(int(s["y"]) + int(s["height"]) - 1, int(_plot.get("railRow", 0))) + EXPORT_REACH
	return cell.x >= left and cell.x <= right and cell.y >= top and cell.y <= bottom


## How many objects of `kind` stand on the plot.
func _count_placed(kind: String) -> int:
	var ids := {}
	for cell: Vector2i in _placed:
		if _placed[cell]["kind"] == kind:
			ids[_placed[cell]["id"]] = true
	return ids.size()


## Whether a tile touches the water, corners included.
func _by_water(cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx != 0 or dy != 0) and _tile(cell + Vector2i(dx, dy)) == WATER:
				return true
	return false


## The mine a drill on `cell` would work: one it touches, corners included; or -1.
func _mine_beside(cell: Vector2i) -> int:
	for id: int in _mines:
		var r := Rect2i(_mine_rect(id))
		if cell.x >= r.position.x - 1 and cell.x <= r.end.x and cell.y >= r.position.y - 1 and cell.y <= r.end.y:
			return id
	return -1


## The tile of the drill working a mine, or (-1, -1).
func _drill_at(mine: int) -> Vector2i:
	for cell: Vector2i in _placed:
		if _placed[cell]["kind"] in DRILLS and _mine_beside(cell) == mine:
			return cell
	return Vector2i(-1, -1)


func _free_ground(cell: Vector2i, mind_player := true) -> bool:
	var spawn: Dictionary = _plot.get("spawn", {})
	return _tile(cell) in [NONE, BRIDGE] and not _fields.has(cell) and not _trees.has(cell) and not _placed.has(cell) \
		and not _animals.has(cell) and cell != Vector2i(spawn.get("x", -1), spawn.get("y", -1)) \
		and (not mind_player or Vector2i(_player.floor_pos.floor()) != cell)


## Whether the player stands on the ground an object of `kind` on `cell` would cover.
func _in_footprint(kind: String, cell: Vector2i) -> bool:
	return Vector2i(_player.floor_pos.floor()) in _footprint(kind, cell)


## Puts up a big building: first walks to the nearest free tile just outside its ground, so the player
## is never walled in by it, then places it.
func _place_big(cell: Vector2i) -> void:
	_stop_work()
	var kind := _placing
	if not _in_footprint(kind, cell) and _near(cell, REACH + Footprints.high(kind)):
		_place_object(cell)
		return
	var low := -Footprints.low(kind) - 1
	var high := Footprints.high(kind) + 1
	var best := Vector2i(-1, -1)
	for dy in range(low, high + 1):
		for dx in range(low, high + 1):
			var at := cell + Vector2i(dx, dy)
			if (dx not in [low, high] and dy not in [low, high]) or _solid(at) or not _astar.region.has_point(at):
				continue
			if best.x < 0 or _player.floor_pos.distance_to(Vector2(at)) < _player.floor_pos.distance_to(Vector2(best)):
				best = at
	if best.x < 0:
		_show_toast("Nie ma jak podejść do tego miejsca. Wybierz inne.", UI.ERROR)
		return
	_walk_to(best, func() -> void:
		if _placing == kind and not _in_footprint(kind, cell):
			_place_object(cell))


## The tiles an object of `kind` standing on `cell` covers (see Footprints).
func _footprint(kind: String, cell: Vector2i) -> Array[Vector2i]:
	return Footprints.tiles(kind, cell)


## Puts a placed object on every tile it covers.
func _put_placed(object: Dictionary) -> void:
	for cell in _footprint(object["kind"], Vector2i(object["tileX"], object["tileY"])):
		_placed[cell] = object


## The tile a placed object stands on, for any tile it covers.
func _anchor(cell: Vector2i) -> Vector2i:
	var object: Dictionary = _placed[cell]
	return Vector2i(object["tileX"], object["tileY"])


## The tile of a placed object the player gets to first: a big building is walked up to on its near side.
func _approach(cell: Vector2i) -> Vector2i:
	if not _placed.has(cell) or not _big(_placed[cell]["kind"]):
		return cell
	var best := cell
	for at in _footprint(_placed[cell]["kind"], _anchor(cell)):
		if _player.floor_pos.distance_to(Vector2(at) + Vector2(0.5, 0.5)) < _player.floor_pos.distance_to(Vector2(best) + Vector2(0.5, 0.5)):
			best = at
	return best


## The name of the crop, planted tree or animal under the mouse and how long until it is ripe.
func _update_field_label(cell: Vector2i) -> void:
	_field_label.visible = (_fields.has(cell) or _trees.has(cell) or _placed.has(cell) or _animals.has(cell)) \
		and _menu_cell.x < 0 and _menu_animal.x < 0
	if not _field_label.visible:
		return
	var crop: Variant = _fields[cell]["crop"] if _fields.has(cell) else null
	if _placed.has(cell):
		_field_label.text = _placed_label(cell)
	elif _animals.has(cell):
		_field_label.text = _animal_label(cell)
	elif _trees.has(cell):
		if _tree_grown(cell):
			_field_label.text = "%s: urosło, zetnij je siekierą%s" % [SPECIES_NAMES.get(_tree_species.get(cell, "pine"), "Drzewo"),
				" · kornik! da tylko kłodę" if _infested.has(cell) else ""]
		else:
			var left := ceili(_tree_left(cell))
			_field_label.text = "Sadzonka: urośnie za %d:%02d" % [left / 60, left % 60]
	elif crop == null:
		_field_label.text = "Zaorane pole: kliknij, aby zasiać"
	elif _ripe(cell):
		_field_label.text = "%s: dojrzała, kliknij, aby zebrać" % _crops[crop]["name"]
	else:
		var left := ceili(_crop_left(cell))
		_field_label.text = "%s: dojrzeje za %d:%02d" % [_crops[crop]["name"], left / 60, left % 60]
	_field_label.reset_size()
	_field_label.position = _screen(_cell_centre(cell)) - Vector2(_field_label.size.x / 2, 70 * _zoom + 24)


func _placed_label(cell: Vector2i) -> String:
	var object: Dictionary = _placed[cell]
	var facing: String = DIRECTIONS[int(object.get("rotation", 0)) & 3]
	if object["kind"] in BELTS:
		return "%s %s: [R] obróć, kliknij, aby schować" % [object["name"], facing]
	if CABLE_STATIONS.has(object["kind"]):
		return "%s %s: wiezie po linie do następnej stacji przed nią (do %d pól). [R] obróć, kliknij, aby schować" \
			% [object["name"], facing, CABLE_STATIONS[object["kind"]]]
	if object["kind"] == UNDERGROUND:
		var role := _logistics.tunnel_role(cell)
		var doing := "chowa przedmioty pod ziemię" if role == "down" else ("wynosi przedmioty spod ziemi" if role == "up" \
			else "postaw drugi taki sam przed nim, do 4 pól dalej")
		return "%s %s, %s: [R] obróć, kliknij, aby schować" % [object["name"], facing, doing]
	if object["kind"] in INSERTERS:
		var held := _logistics.held(cell)
		var count := _logistics.held_count(cell)
		var carrying := ", niesie: %s%s" % [_item_name(held).to_lower(), " ×%d" % count if count > 1 else ""] if held != "" else ""
		return "%s %s%s%s%s: [R] obróć, kliknij, aby schować albo ustawić filtr" % [object["name"], facing, carrying, _filter_note(object["id"]), _power_note(object["id"])]
	if object["kind"] == SPLITTER:
		var filter := _logistics.splitter(object["id"])
		var sorting := "na zmianę w lewo i w prawo" if (filter["items"] as Array).is_empty() \
			else "wybrane %s" % ("w lewo" if int(filter["side"]) == 0 else "w prawo")
		return "Rozdzielacz %s, %s: [R] obróć, kliknij po więcej" % [facing, sorting]
	var summary := _logistics.storage(object["id"])
	if not summary.is_empty():
		var fill := "%d/%d miejsc" % [int(summary["usedSlots"]), int(summary["slots"])] if int(summary["slots"]) > 1 \
			else "%d/%d" % [int(summary["stored"]), int(summary["capacity"])]
		return "%s (%s)%s: kliknij, aby otworzyć" % [object["name"], fill, _filter_note(object["id"])]
	if object["kind"] == COMPUTER:
		return "%s: kliknij, aby otworzyć rynek" % object["name"]
	if FORESTERS.has(object["kind"]):
		var forester: Dictionary = _foresters.get(object["id"], {})
		if forester.is_empty():
			return "%s: kliknij, aby otworzyć" % object["name"]
		var full := ", pełny" if forester.get("full", false) else ""
		return "%s (drewno %d/%d%s, drzew %d): kliknij, aby otworzyć" % [object["name"], int(forester["wood"]), int(forester["capacity"]), full, int(forester["trees"])]
	if FARMSTEADS.has(object["kind"]):
		var farm: Dictionary = _farmsteads.get(object["id"], {})
		if farm.is_empty():
			return "%s: kliknij, aby otworzyć" % object["name"]
		var full := ", pełna" if farm.get("full", false) else ""
		return "%s (plony %d/%d%s, grządek %d): kliknij, aby otworzyć" % [object["name"], int(farm["crops"]), int(farm["capacity"]), full, int(farm["fields"])]
	if object["kind"] == CANTEEN:
		return "%s: kliknij, aby wydać jedzenie załogom" % object["name"]
	if object["kind"] in [STABLE, BELLOWS]:
		return object["name"]
	if object["kind"] == POLE:
		return "Słup energetyczny (%s): kliknij po więcej" % _power.describe(object["id"])
	if object["kind"] in GENERATORS:
		return "%s%s: kliknij, aby dołożyć opału" % [object["name"], _power_note(object["id"])]
	if object["kind"] in WELLS:
		return "%s%s: kliknij, aby zobaczyć szyb" % [object["name"], _power_note(object["id"]) if _power.runs_on_power(object["kind"]) else ""]
	if object["kind"] == ROAD:
		return "%s: po asfalcie chodzisz szybciej. Kliknij, aby schować" % object["name"]
	if object["kind"] in HYDRO:
		return "%s (woda kręci nim bez opału): kliknij po więcej" % object["name"]
	if object["kind"] in SOLAR:
		return "%s (słońce daje prąd za dnia, bez opału): kliknij po więcej" % object["name"]
	if object["kind"] == BATTERY:
		return "%s (%s): kliknij po więcej" % [object["name"], _power.describe_battery(object["id"])]
	if object["kind"] in WIND:
		return "%s (wiatr daje prąd bez opału): kliknij po więcej" % object["name"]
	if object["kind"] == HEATER:
		return "%s (grzeje maszyny %d pola wokół): kliknij, aby dołożyć opału" % [object["name"], int(_plot.get("frost", {}).get("heaterReach", 3)) if _plot.get("frost") != null else 3]
	if object["kind"] == TRACK_FOUNDATION:
		return "%s: pociągi przez lodowiec jadą tu z normalną prędkością. Kliknij, aby schować" % object["name"]
	if object["kind"] == "furniture_dog_kennel":
		return "%s: wyślesz sanie z psim zaprzęgiem ze stacji, bez opłaty. Kliknij, aby schować" % object["name"]
	if object["kind"] == "furniture_snowmobile_garage":
		return "%s: wyślesz skuter ze stacji, szybko i za benzynę. Kliknij, aby schować" % object["name"]
	if object["kind"] in TOURISM:
		return "%s%s: kliknij, aby odebrać utarg" % [object["name"], " (zorza! turyści płacą potrójnie)" if _aurora_now() else ""]
	if _power.cold(object["id"]):
		return "%s (zmarzła: pracuje o połowę wolniej, postaw kocioł grzewczy obok)%s: kliknij, aby użyć" % [object["name"], _power_note(object["id"])]
	if object["kind"] == REED_FENCE:
		return "%s: chroni panele i wykopane wydmy przed burzą piaskową. Kliknij, aby schować" % object["name"]
	if object["kind"] in DRILLS:
		return "%s%s: kliknij, aby zobaczyć urobek" % [object["name"], _power_note(object["id"])]
	return "%s%s: kliknij, aby użyć" % [object["name"], _power_note(object["id"]) if _power.runs_on_power(object["kind"]) else ""]


## The item an object's filter lets through, as a note after its name; "" without a filter.
func _filter_note(id: String) -> String:
	var only := _logistics.filter(id)
	return ", filtr: %s" % _filter_name(only).to_lower() if only != "" else ""


func _filter_name(item: String) -> String:
	return _logistics.names.get(item, _item_name(item))


## How a machine that runs on power is doing, as a note after its name; "" with full power.
func _power_note(id: String) -> String:
	if _power.network(id).is_empty():
		return " (bez prądu: postaw słup najwyżej 2 pola obok)"
	var speed := _power.speed(id)
	if speed <= 0.0:
		return " (bez prądu: generator wygasł)"
	if speed < 0.999:
		return " (za mało prądu: %d%%)" % roundi(speed * 100.0)
	return ""


func _draw_marks() -> void:
	_draw_power_reach()
	if _hold_id != "":
		_draw_hold()
	if _hovered.x >= 0 and WORK.has(_work_kind(_hovered)) and not _fields.has(_hovered):
		var ok := _holds(WORK[_work_kind(_hovered)]["tool"])
		_draw_ring(_cell_centre(_hovered), Color(0.96, 0.69, 0.25, 0.8) if ok else Color(1.0, 0.42, 0.35, 0.8))
	var ground := _ground_cell()
	if _hovered.x >= 0 and (_placed.has(_hovered) or _animals.has(_hovered)):
		var big := _placed.has(_hovered) and _big(_placed[_hovered]["kind"])
		if big:
			_draw_footprint(_placed[_hovered]["kind"], _anchor(_hovered), Color(0.96, 0.69, 0.25, 0.8))
			_draw_ring(_object_centre(_placed[_hovered]["kind"], _anchor(_hovered)), Color(0.96, 0.69, 0.25, 0.8), _ring_size(_placed[_hovered]["kind"]))
		else:
			_draw_ring(_cell_centre(_hovered), Color(0.96, 0.69, 0.25, 0.8))
		if big and (FORESTERS.has(_placed[_hovered]["kind"]) or FARMSTEADS.has(_placed[_hovered]["kind"])):
			_draw_forest(_placed[_hovered]["kind"], _hovered, int(_placed[_hovered].get("rotation", 0)))
	if _placing != "" and ground.x >= 0:
		if FORESTERS.has(_placing) or FARMSTEADS.has(_placing):
			_draw_forest(_placing, ground, _place_rotation)
		var tint := Color(0.56, 0.84, 0.35, 0.8) if _can_place(ground) else Color(1.0, 0.42, 0.35, 0.8)
		_draw_footprint(_placing, ground, tint)
		_draw_ring(_object_centre(_placing, ground), tint, _ring_size(_placing))
		_draw_ghost(ground)
	elif _releasing != "" and ground.x >= 0:
		_draw_ring(_cell_centre(ground), Color(0.56, 0.84, 0.35, 0.8) if _can_release(ground) else Color(1.0, 0.42, 0.35, 0.8))
	elif _hovered.x < 0 and (_fields.has(ground) or _can_till(ground) or _can_plant(ground)):
		_draw_ring(_cell_centre(ground), Color(0.56, 0.84, 0.35, 0.8))
	if _work.x >= 0:
		_draw_ring(_cell_centre(_work), Color(1, 1, 1, 0.7))


## The tiles poles power, on the ground: of every pole while a pole, a generator or a machine that
## runs on power is being placed (with the wires a new pole would get), and of a pole under the mouse.
func _draw_power_reach() -> void:
	var placing_power: bool = _placing == POLE or _placing in GENERATORS or _placing in HYDRO or _power.runs_on_power(_placing)
	var hovered_pole: bool = _hovered.x >= 0 and _placed.has(_hovered) and _placed[_hovered]["kind"] == POLE
	if not placing_power and not hovered_pole:
		return
	var areas: Array[Vector2i] = _power.poles()
	if not placing_power:
		areas = [_hovered]
	var ground := _ground_cell()
	if _placing == POLE and ground.x >= 0:
		areas.append(ground)
	var fill := Color(1.0, 0.82, 0.3, 0.07)
	for pole in areas:
		var r := _power.supply_radius
		var rect := Rect2(Vector2(pole - Vector2i(r, r)) * TILE, Vector2(2 * r + 1, 2 * r + 1) * TILE)
		var strong := pole == ground or pole == _hovered
		_marks.draw_rect(rect, Color(fill, 0.13) if strong else fill)
		_marks.draw_rect(rect, Color(1.0, 0.82, 0.3, 0.75 if strong else 0.3), false, 2.0)
	if _placing == POLE and ground.x >= 0:
		for pole in _power.poles():
			if _power.wired(pole, ground):
				_marks.draw_dashed_line(_cell_centre(ground), _cell_centre(pole), Color(1.0, 0.82, 0.3, 0.8), 2.0, 8.0)


## What is being placed, see-through on the tile under the mouse, with the way it will face.
func _draw_ghost(cell: Vector2i) -> void:
	var sprite: String = PlotLogistics.BELT_SPRITES[_place_rotation] + PlotLogistics.tier_suffix(_placing) if _placing in BELTS \
		else PlotLogistics.TUNNEL_SPRITES[(_place_rotation + 2) & 3] if _placing == UNDERGROUND else PLACED_SPRITES.get(_placing, "")
	if sprite == "" or not _layout.has(sprite):
		return
	var texture: Texture2D = _grown_textures[sprite] if _grown_textures.has(sprite) else load("res://art/plot/%s.png" % sprite)
	_marks.draw_texture(texture, _cell_centre(cell) - _sprite_anchor(sprite), Color(1, 1, 1, 0.55))
	if _placing in MACHINERY:
		var dir := Vector2(PlotLogistics.facing(_place_rotation)) * TILE
		var from := _cell_centre(cell) - dir * 0.35 - Vector2(0, 10)
		var to := _cell_centre(cell) + dir * 0.45 - Vector2(0, 10)
		var head := (to - from).normalized()
		var side := Vector2(-head.y, head.x)
		var color := Color(0.56, 0.84, 0.35, 0.95)
		_marks.draw_line(from, to, color, 3.0, true)
		_marks.draw_colored_polygon([to + head * 4, to - head * 9 + side * 7, to - head * 9 - side * 7], color)


## The tiles a machine of more than one tile covers, on the ground, so it shows where inserters fit along its sides.
func _draw_footprint(kind: String, cell: Vector2i, color: Color) -> void:
	if Footprints.size(kind) < 2:
		return
	for tile in Footprints.tiles(kind, cell):
		var rect := Rect2(Vector2(tile) * TILE, TILE).grow(-2.0)
		_marks.draw_rect(rect, Color(color, 0.12))
		_marks.draw_rect(rect, Color(color, 0.55), false, 1.5)


func _draw_ring(at: Vector2, color: Color, size := 1.0) -> void:
	_marks.draw_set_transform(at, 0, Vector2(1, TILE.y / TILE.x))
	_marks.draw_arc(Vector2.ZERO, TILE.x * 0.55 * size, 0, TAU, 40, color, 2.5, true)
	_marks.draw_set_transform(Vector2.ZERO)


## The square a forester keeps its forest in (or a farmstead its fields), on the ground, with its clearing and the path
## from its door left free.
func _draw_forest(kind: String, cell: Vector2i, rotation: int) -> void:
	var r: int = FORESTERS[kind] if FORESTERS.has(kind) else FARMSTEADS[kind]
	var area := Rect2(Vector2(cell - Vector2i(r, r)) * TILE, Vector2(2 * r + 1, 2 * r + 1) * TILE)
	var tint := Color(0.45, 0.85, 0.35) if FORESTERS.has(kind) else Color(0.9, 0.75, 0.3)
	_marks.draw_rect(area, Color(tint, 0.10))
	_marks.draw_rect(area, Color(tint, 0.7), false, 2.0)
	var c := FOREST_CLEARING
	var clearing := Rect2(Vector2(cell - Vector2i(c, c)) * TILE, Vector2(2 * c + 1, 2 * c + 1) * TILE)
	var facing := PlotLogistics.facing(rotation)
	var across := (Vector2i.ONE - facing.abs()) * FOOTPRINT
	var path_from := cell + facing * (c + 1) - across
	var path_to := cell + facing * r + across
	var path := Rect2(Vector2(path_from.min(path_to)) * TILE, Vector2((path_to - path_from).abs() + Vector2i.ONE) * TILE)
	for free: Rect2 in [clearing, path]:
		_marks.draw_rect(free, Color(0.95, 0.85, 0.5, 0.12))
		_marks.draw_rect(free, Color(0.95, 0.85, 0.5, 0.45), false, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_play or _pinch_zoom(event):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom * 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom / 1.1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_update_hover()
			_start_hold(MOUSE_BUTTON_RIGHT)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_update_hover()
			# On a touch screen a long press does what holding the right button does; the tap acts as always.
			if event.device == InputEvent.DEVICE_ID_EMULATION:
				_start_hold(MOUSE_BUTTON_LEFT)
			var cell := Vector2i((get_global_mouse_position() / TILE).floor())
			if _placing != "":
				if _can_place(cell) and _big(_placing):
					_place_big(cell)
				elif _can_place(cell):
					_go_and(cell, _place_object, true)
				else:
					_show_toast("Tu nie można tego postawić. Wybierz wolne pole.", UI.ERROR)
			elif _releasing != "":
				if _can_release(cell):
					_go_and(cell, _release_animal, true)
				else:
					_show_toast("Tu nie można wypuścić zwierzęcia. Wybierz wolne pole.", UI.ERROR)
			elif _hovered.x >= 0:
				_act_on(_hovered)
			elif _hover_station:
				_go_to_station()
			elif _hover_mine >= 0:
				_go_to_mine(_hover_mine)
			elif _fields.has(cell) or _animals.has(cell) or _tile(cell) in [WATER, CREVASSE]:
				_act_on(cell)
			elif _can_plant(cell):
				_go_and(cell, _plant_tree)
			elif _can_till(cell):
				_till(cell)
			else:
				_stop_work()
				if _tile(cell) >= 0:
					_walk_to(cell)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		if _placing != "":
			_stop_placing()
		elif _releasing != "":
			_stop_releasing()
		elif _station_window.visible or _inventory_window.visible or _stats_window.visible or _company_window.visible or _achievements_window.visible \
				or _mine_window.visible or _character_window.visible or _bank_window.visible or _using_window_open():
			for window: GameWindow in [_station_window, _inventory_window, _crafting_window, _research_window, _furnace_window, _machine_window, _forester_window, _farmstead_window, _canteen_window, _generator_window, _storage_window, _splitter_window, _filter_window, _stats_window, _company_window, _achievements_window, _mine_window, _market_window, _character_window, _bank_window]:
				window.hide_window()
		elif _planting:
			_set_planting(false)
		else:
			_stop_work()
			_path = PackedVector2Array()
	elif event.is_action_pressed("rotate"):
		if _placing != "":
			_place_rotation = (_place_rotation + 1) % 4
			_update_hint()
		elif _turnable(_hovered):
			_rotate_placed(_hovered)
	elif event.is_action_pressed("interact"):
		if _nearest_placed().x >= 0:
			var at := _nearest_placed()
			if _using == at and _using_window_open():
				_hide_placed_windows()
			else:
				_use_placed(at)
		elif _near_station():
			_station_window.toggle()
			if _station_window.visible:
				_refresh_station()
		elif _nearest_mine() >= 0 and _nearest_work().x < 0:
			_go_to_mine(_nearest_mine())
		else:
			var cell := _nearest_work()
			if cell.x >= 0:
				_act_on(cell)
	elif event.is_action_pressed("inventory"):
		_inventory_window.toggle()
		if _inventory_window.visible:
			_reload_inventory()
	elif event.is_action_pressed("station"):
		_go_to_station()
	elif event.is_action_pressed("company"):
		_company_window.toggle()
	elif event.is_action_pressed("bank"):
		_bank_window.toggle()
	elif event.is_action_pressed("stats"):
		_stats_window.toggle()
	elif event.is_action_pressed("achievements"):
		_achievements_window.toggle()
	elif event.is_action_pressed("character"):
		_character_window.toggle()
	elif event.is_action_pressed("tool"):
		_tool_slot.open()
	elif event.is_action_pressed("plant"):
		_set_planting(not _planting)
	elif event.is_action_pressed("market"):
		_toggle_market()
	elif event.is_action_pressed("upgrade_mine"):
		_toggle_mine_window()
	elif event.is_action_pressed("world_map"):
		Game.open_world_map()
	elif event.is_action_pressed("garage"):
		Game.open_garage()


## Zooms with two fingers on a touch screen or a pinch on a touchpad; true if it did.
func _pinch_zoom(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		_set_zoom(_zoom * event.factor)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch = 0.0
		return false
	elif event is InputEventScreenDrag and _touches.size() == 2:
		_touches[event.index] = event.position
		var distance: float = _touches.values()[0].distance_to(_touches.values()[1])
		if _pinch > 0.0:
			_set_zoom(_zoom * distance / _pinch)
		_pinch = distance
	else:
		return false
	get_viewport().set_input_as_handled()
	return true


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2.ONE * _zoom


# --- Working trees, rocks and dunes ----------------------------------------------------------

func _near(cell: Vector2i, distance := REACH) -> bool:
	return _player.floor_pos.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) <= distance


func _nearest_work() -> Vector2i:
	var best := Vector2i(-1, -1)
	var here := Vector2i(_player.floor_pos.floor())
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cell := here + Vector2i(dx, dy)
			# The water is fished only with a rod in hand; E by the shore without one does the other work.
			var kind := _work_kind(cell)
			if kind == WATER and not _holds(WORK[WATER]["tool"]):
				continue
			if (WORK.has(kind) or _ripe(cell)) and _near(cell) and (best.x < 0 or _player.floor_pos.distance_to(Vector2(cell)) < _player.floor_pos.distance_to(Vector2(best))):
				best = cell
	return best


## Whether a tool in the tool bar does the work of `tool`.
func _holds(tool: String) -> bool:
	if tool == "":
		return true
	return Game.tools().any(func(held: Dictionary) -> bool: return held["id"] == tool or STANDS_IN.get(held["id"], "") == tool)


## The tool bar may have changed elsewhere (a tool that came with a plot): fetches it again.
func _sync_tool_bar() -> void:
	await Game.reload_character()
	_tool_slot.refresh()
	_update_hint()


## Walks up to a tree, rock or dune and works it with the tool in hand, or pulls out a bush by hand.
func _work_on(cell: Vector2i) -> void:
	var kind := _work_kind(cell)
	if _trees.has(cell) and not _tree_grown(cell):
		var left := ceili(_tree_left(cell))
		_show_toast("Sadzonka urośnie za %d:%02d." % [left / 60, left % 60], UI.MUTED)
		return
	if not WORK.has(kind):
		_show_toast("%s: nie da się tego zebrać." % OBJECT_NAMES.get(kind, "To"), UI.MUTED)
		return
	var work: Dictionary = WORK[kind]
	if not _holds(work["tool"]):
		_show_toast("%s: potrzebujesz %s. Zmień narzędzie w slocie [Q]." % [work["name"], work["need"]], UI.ERROR)
		return
	_stop_work()
	if _near(cell):
		_start_work(cell)
		return
	_walk_to(cell, func() -> void:
		if _near(cell) and _work_kind(cell) == kind:
			_start_work(cell)
		elif _work_kind(cell) == kind:
			_show_toast("Nie da się tam podejść.", UI.ERROR), true)


func _start_work(cell: Vector2i, mode := "harvest") -> void:
	_work = cell
	_work_mode = mode
	# Cutting a tree down takes longer than a swing at a rock or a dune, unless with a saw.
	_work_seconds = _harvest_seconds
	if mode == "harvest" and _work_kind(cell) in TREES:
		_work_seconds = _tree_seconds()
	if mode == "harvest" and _work_kind(cell) in [ROCK, ICE_BLOCK]:
		_work_seconds = float(_plot.get("rockSeconds", _harvest_seconds)) / _pickaxe_speed()
	if mode == "harvest" and _work_kind(cell) == METEORITE:
		_work_seconds = 2.0 * float(_plot.get("rockSeconds", _harvest_seconds)) / _pickaxe_speed()
	if mode == "harvest" and _work_kind(cell) == WATER:
		_work_seconds = float(_plot.get("fishSeconds", _harvest_seconds))
	if mode == "mine":
		_work_seconds = _mine_seconds / _pickaxe_speed()
	_work_seconds /= _outfit_speed(_industry(cell, mode))
	_work_left = _work_seconds
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	_work_bar.max_value = _work_seconds
	_work_bar.visible = true


## The industry a job is part of, for the bonus of the clothes worn (as the server's HarvestRules.Industry).
func _industry(cell: Vector2i, mode: String) -> String:
	if mode == "mine":
		return "mining"
	if mode == "till":
		return "farming"
	var kind := _work_kind(cell)
	if kind in TREES or kind in [BUSH, MUSHROOMS]:
		return "forestry"
	if kind in [ROCK, ICE_BLOCK, METEORITE, SNOWDRIFT]:
		return "mining"
	if kind == WATER:
		return "fishing"
	return ""


## How many times faster the clothes worn make a job of `industry`.
func _outfit_speed(industry: String) -> float:
	var bonuses: Variant = Game.character.get("bonuses")
	return 1.0 + (float(bonuses.get(industry, 0)) / 100.0 if bonuses is Dictionary else 0.0)


## How long the best saw in the tool bar (or the axe) takes to cut a tree.
func _tree_seconds() -> float:
	var best := _chop_seconds
	var saws: Dictionary = _plot.get("saws", {"tool_chainsaw": {"seconds": _saw_seconds}})
	for held: Dictionary in Game.tools():
		if saws.has(held["id"]):
			best = minf(best, float(saws[held["id"]]["seconds"]))
	return best


## How many times faster than an iron pickaxe the best pickaxe in the tool bar breaks rock.
func _pickaxe_speed() -> float:
	var best := 1.0
	var speeds: Dictionary = _plot.get("pickaxes", {})
	for held: Dictionary in Game.tools():
		best = maxf(best, float(speeds.get(held["id"], 0.0)))
	return best


func _stop_work() -> void:
	_work = Vector2i(-1, -1)
	_work_mine = -1
	_work_bar.visible = false
	_player.rotation = 0.0


func _update_work(delta: float) -> void:
	if _work.x < 0:
		return
	_work_left -= delta
	_work_bar.value = _work_seconds - _work_left
	_work_bar.position = _screen(_cell_centre(_work)) - Vector2(_work_bar.size.x / 2, 90 * _zoom + 12)
	# Swing: the body leans into each stroke.
	_player.rotation = sin((_work_seconds - _work_left) * TAU * 2.0) * 0.08
	if _work_left <= 0.0:
		var cell := _work
		var mine := _work_mine
		_stop_work()
		if _work_mode == "till":
			_till_request(cell)
		elif _work_mode == "mine":
			_mine_request(mine)
		else:
			_harvest(cell)


func _harvest(cell: Vector2i) -> void:
	var kind := _tile(cell)
	var reply := await Net.request("plot.harvest", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] != "plot.harvested":
		_show_error(reply)
		if reply["payload"].get("code", "") == "nothing_here":
			_clear_tile(cell, kind)
		return
	var result: Dictionary = reply["payload"]
	_clear_tile(cell, kind)
	# A saw may fell the trees next to it at the same cut.
	for felled: Dictionary in result.get("felled", []):
		var other := Vector2i(int(felled["tileX"]), int(felled["tileY"]))
		_clear_tile(other, _tile(other))
	var items: Array = result["items"]
	for i in items.size():
		var item: Dictionary = items[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, _cell_centre(cell), i * 0.25, item["id"])
		if item["id"] in SAPLINGS:
			_sapling_counts[item["id"]] = int(_sapling_counts.get(item["id"], 0)) + int(item["quantity"])
			if item["id"] == _planting_sapling:
				_set_saplings(_saplings + int(item["quantity"]))
	var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(cell), items.size() * 0.25)
	Game.gain_xp(result["xp"])
	_refresh_character()
	if result["xp"].get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(result["xp"]["level"]), UI.GOLD)
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()


## Removes a worked object: it falls over (a tree) or crumbles, and the tile becomes free.
func _clear_tile(cell: Vector2i, kind: int) -> void:
	if kind == CREVASSE:
		# A bridge now lies over the crevasse: it is walked over and built on.
		_tiles[cell.y * _size + cell.x] = BRIDGE
		_astar.set_point_solid(cell, false)
		_draw_cell(cell)
		_set_minimap(cell, BRIDGE)
		return
	if _trees.has(cell):
		var sprite := _sprite_at(cell)
		_trees.erase(cell)
		if _hovered == cell:
			_hovered = Vector2i(-1, -1)
		_draw_cell(cell)
		_set_minimap(cell, NONE)
		_vanish(sprite, cell, true)
		return
	if not SPRITES.has(kind):
		return
	var sprite_name := _variant(kind, cell)
	_tiles[cell.y * _size + cell.x] = NONE
	# Snow dug off something that stands there leaves it as solid as it was.
	_astar.set_point_solid(cell, _placed.has(cell) and not _walkable(cell))
	if _hovered == cell:
		_hovered = Vector2i(-1, -1)
	_draw_cell(cell)
	_set_minimap(cell, NONE)
	_vanish(sprite_name, cell, kind in TREES)


## A copy of a sprite that falls over (a tree) or sinks into the ground, then disappears.
func _vanish(sprite_name: String, cell: Vector2i, fall: bool) -> void:
	var falling := Sprite2D.new()
	falling.texture = load("res://art/plot/%s.png" % sprite_name)
	falling.centered = false
	falling.offset = -Vector2(_layout[sprite_name]["anchorX"], _layout[sprite_name]["anchorY"])
	falling.position = _cell_centre(cell)
	_sorted.add_child(falling)
	var tween := create_tween()
	if fall:
		var side := 1.0 if _player.floor_pos.x < cell.x + 0.5 else -1.0
		tween.tween_property(falling, "rotation", side * PI / 2.2, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(falling, "modulate:a", 0.0, 0.4)
	else:
		tween.tween_property(falling, "scale", Vector2(1.15, 0.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(falling, "modulate:a", 0.0, 0.35)
	tween.tween_callback(falling.queue_free)


# --- Farming ------------------------------------------------------------------------------------

## What a click on a tile does: work nature, sow an empty field, reap a ripe crop, tend an animal.
func _act_on(cell: Vector2i) -> void:
	if _tile(cell) == SNOWDRIFT:
		_work_on(cell)  # whatever is buried is dug out first
		return
	if _turnable(cell) or (_placed.has(cell) and _placed[cell]["kind"] in MENU_ONLY):
		_open_object_menu(cell)
		return
	if _placed.has(cell):
		_go_and(_approach(cell), _use_placed)
		return
	if _animals.has(cell):
		_open_animal_menu(cell)
		return
	if not _fields.has(cell):
		_work_on(cell)
		return
	var crop: Variant = _fields[cell]["crop"]
	if crop == null:
		_open_crop_menu(cell)
	elif _ripe(cell):
		_go_and(cell, _reap)
	else:
		var left := ceili(_crop_left(cell))
		_show_toast("%s dojrzeje za %d:%02d." % [_crops[crop]["name"], left / 60, left % 60], UI.MUTED)


## Walks onto or next to a tile (always next to it with `next_to`), then calls `action` with it.
func _go_and(cell: Vector2i, action: Callable, next_to := false) -> void:
	_stop_work()
	if _near(cell) and not (next_to and Vector2i(_player.floor_pos.floor()) == cell):
		action.call(cell)
		return
	_walk_to(cell, func() -> void:
		if _near(cell):
			action.call(cell), _solid(cell) or next_to)


func _till(cell: Vector2i) -> void:
	_go_and(cell, func(at: Vector2i) -> void:
		if _can_till(at):
			_start_work(at, "till"))


func _till_request(cell: Vector2i) -> void:
	var reply := await Net.request("plot.till", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	_apply_field(reply)


func _open_crop_menu(cell: Vector2i) -> void:
	_menu_cell = cell
	_crop_menu.clear()
	for i in CROPS.size():
		var crop: Dictionary = _crops.get(CROPS[i], {})
		if crop.is_empty():
			continue
		var minutes := roundi(float(crop["growSeconds"]) / 60.0)
		_crop_menu.add_icon_item(UI.texture("icons/item_" + CROPS[i]),
			"%s  ·  %d min  ·  %d szt." % [crop["name"], minutes, int(crop["yield"])], i)
	# With fertiliser in the bag, each crop can be sown with it too, and ripens twice as fast.
	if _count(FERTILIZER) > 0:
		_crop_menu.add_separator("Z nawozem (masz %d)" % _count(FERTILIZER))
		for i in CROPS.size():
			var crop: Dictionary = _crops.get(CROPS[i], {})
			if crop.is_empty():
				continue
			var minutes := roundi(float(crop["growSeconds"]) / 60.0 / FERTILIZER_SPEED)
			_crop_menu.add_icon_item(UI.texture("icons/item_" + FERTILIZER),
				"%s z nawozem  ·  %d min" % [crop["name"], maxi(1, minutes)], FERTILIZED + i)
	if _count(MANURE) > 0:
		_crop_menu.add_separator("Na oborniku (masz %d)" % _count(MANURE))
		for i in CROPS.size():
			var crop: Dictionary = _crops.get(CROPS[i], {})
			if crop.is_empty():
				continue
			var minutes := roundi(float(crop["growSeconds"]) / 60.0 / MANURE_SPEED)
			_crop_menu.add_icon_item(UI.texture("icons/item_" + MANURE),
				"%s na oborniku  ·  %d min" % [crop["name"], maxi(1, minutes)], MANURED + i)
	_crop_menu.reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(12, 4)
	_crop_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_crop_chosen(index: int) -> void:
	var cell := _menu_cell
	_menu_cell = Vector2i(-1, -1)
	var manure := index >= MANURED
	var fertilize := not manure and index >= FERTILIZED
	var crop: String = CROPS[index - MANURED if manure else index - FERTILIZED if fertilize else index]
	_go_and(cell, func(at: Vector2i) -> void: _plant(at, crop, fertilize, manure))


func _plant(cell: Vector2i, crop: String, fertilize := false, manure := false) -> void:
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.plant", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y, "crop": crop,
		"fertilize": fertilize, "manure": manure})
	_apply_field(reply)
	if fertilize or manure:
		_reload_inventory()


func _reap(cell: Vector2i) -> void:
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var sprite := _sprite_at(cell)
	var reply := await Net.request("plot.reap", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] == "plot.field" and sprite != "":
		_vanish(sprite, cell, false)
	_apply_field(reply)


## Shows the server's answer to tilling, sowing or reaping.
func _apply_field(reply: Dictionary) -> void:
	if reply["type"] != "plot.field":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var field: Dictionary = result["field"]
	var cell := Vector2i(field["tileX"], field["tileY"])
	_fields[cell] = {"crop": field["crop"], "readyAt": field["readyAt"]}
	_draw_cell(cell)
	_set_minimap(cell, NONE)
	var items: Array = result["items"]
	for i in items.size():
		var item: Dictionary = items[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, _cell_centre(cell), i * 0.25, item["id"])
	if result.get("xp") != null:
		var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
		if gained > 0:
			_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(cell), items.size() * 0.25)
		Game.gain_xp(result["xp"])
		_refresh_character()
	if not items.is_empty() and (_inventory_window.visible or _station_window.visible):
		_reload_inventory()


# --- Forestry -----------------------------------------------------------------------------------

func _apply_pests(pests: Dictionary) -> void:
	_infested = {}
	for tile: Dictionary in pests.get("infested", []):
		_infested[Vector2i(tile["tileX"], tile["tileY"])] = true


## What happened in the forest while the player was away: a fire, the bark beetle in a monoculture.
func _show_forest_news(plot: Dictionary) -> void:
	var fire: Variant = plot.get("fire")
	if fire is Dictionary:
		var when := Time.get_datetime_string_from_unix_time(int(float(fire["at"]) / 1000.0), true).substr(5, 11).replace("T", " ")
		if fire["stopped"]:
			_show_toast("Strażnica ugasiła pożar lasu (%s), zanim się rozprzestrzenił." % when, UI.GOLD)
		else:
			_show_toast("Pożar lasu (%s)! Spłonęło %d drzew. Przecinki, wieża obserwacyjna i strażnica powstrzymają następny." % [when, int(fire["burnt"])], UI.ERROR)
	var pests: Dictionary = plot.get("pests", {})
	if pests.get("monoculture") != null and pests.get("sprayedUntil") == null:
		_show_toast("Kornik! Twoje drzewa to monokultura (%s): dziś zżera %d z nich. Sadź różne gatunki albo opryskaj las środkiem na kornika." % [
			SPECIES_NAMES.get(pests["monoculture"], "?").to_lower(), (pests.get("infested", []) as Array).size()], UI.ERROR)


## The forest certificate, for the planting button's tooltip.
func _certificate_note() -> String:
	var certificate: Dictionary = _plot.get("certificate", {})
	if certificate.is_empty():
		return ""
	if certificate["certified"]:
		return "\nCertyfikat leśny: masz go, handlarz płaci za drewno, deski i belki o %d%% więcej." % int(certificate["bonusPercent"])
	return "\nCertyfikat leśny: posadź w %d dni co najmniej %d drzew i nie mniej, niż ściąłeś (teraz %d posadzonych, %d ściętych), a drewno sprzedasz o %d%% drożej." % [
		int(certificate["days"]), int(certificate["needed"]), int(certificate["planted"]), int(certificate["cut"]), int(certificate["bonusPercent"])]


func _spray_forest() -> void:
	var reply := await Net.request("forest.spray", {"x": _at.x, "y": _at.y})
	if reply["type"] != "forest.pests":
		_show_error(reply)
		return
	_apply_pests(reply["payload"])
	_show_toast("Opryskane: kornik nie tknie twoich drzew przez 3 dni.", UI.GOLD)
	_reload_inventory()


## Turns planting on or off: while on, a click on free ground plants a sapling from the inventory.
func _set_planting(on: bool) -> void:
	if on and _tree_grow_seconds <= 0.0:
		_show_toast("Na lodowcu i w górach drzewa nie rosną.", UI.ERROR)
		on = false
	elif on and _saplings <= 0:
		_show_toast("Nie masz sadzonek. Kupisz je na rynku w garażu (od handlarza albo od innych graczy).", UI.ERROR)
		on = false
	_planting = on
	if on:
		_stop_work()
		_stop_releasing()
		var kind: Dictionary = _tree_kinds.get(_planting_sapling, {})
		var minutes := _grow_seconds(kind.get("id", "pine")) / 60.0
		_show_toast("Sadzenie: kliknij wolne pole. %s urośnie tu w %s min." % [SPECIES_NAMES.get(kind.get("id", "pine"), "Drzewo"),
			str(snappedf(minutes, 0.1)).trim_suffix(".0").replace(".", ",")])
	_update_plant_button()
	_update_hint()


func _set_saplings(count: int) -> void:
	_saplings = maxi(count, 0)
	if _saplings == 0:
		_planting = false
	_update_plant_button()
	_update_hint()


func _update_plant_button() -> void:
	if _plant_button == null:
		return
	_plant_count.text = str(_saplings)
	_plant_button.tooltip_text = ("Koniec sadzenia  [P]" if _planting else "Sadź drzewa  [P]") \
		+ "\n%s: %d. Kupisz je na rynku w garażu albo przy komputerze na działce. Z każdego ściętego drzewa jest szansa na nową." % [_item_name(_planting_sapling), _saplings] \
		+ "\nInny gatunek wybierzesz, klikając jego sadzonkę w ekwipunku." + _certificate_note()
	_plant_button.modulate = Color(0.75, 1.0, 0.6) if _planting else Color.WHITE


## Saplings in the inventory, counted from an "inventory" reply.
func _count_saplings(items: Array) -> void:
	_sapling_counts = {}
	for item: Dictionary in items:
		if item["id"] in SAPLINGS:
			_sapling_counts[item["id"]] = int(_sapling_counts.get(item["id"], 0)) + int(item["quantity"])
	# Out of the kind being planted, the next kind there is goes in.
	if int(_sapling_counts.get(_planting_sapling, 0)) == 0:
		for sapling: String in SAPLINGS:
			if int(_sapling_counts.get(sapling, 0)) > 0:
				_planting_sapling = sapling
				break
	_set_saplings(int(_sapling_counts.get(_planting_sapling, 0)))


func _plant_tree(cell: Vector2i) -> void:
	if not _can_plant(cell):
		return
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var sapling := _planting_sapling
	var reply := await Net.request("plot.plantTree", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y, "sapling": sapling})
	if reply["type"] != "plot.tree":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var tree: Dictionary = result["tree"]
	var at := Vector2i(tree["tileX"], tree["tileY"])
	_trees[at] = tree["readyAt"]
	_tree_species[at] = tree.get("species", "pine")
	_draw_cell(at)
	_set_minimap(at, NONE)
	_float_text("−1 %s" % _item_name(sapling), UI.MUTED, _cell_centre(at), 0.0, sapling)
	var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(at), 0.25)
	Game.gain_xp(result["xp"])
	_refresh_character()
	_sapling_counts[sapling] = maxi(int(_sapling_counts.get(sapling, 0)) - 1, 0)
	_set_saplings(_saplings - 1)
	if _saplings == 0:
		_show_toast("To była ostatnia sadzonka.", UI.MUTED)
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()


# --- Husbandry -----------------------------------------------------------------------------------

## Starts letting an animal from the inventory out: a click on free ground puts it there.
func _start_releasing(kind: String) -> void:
	if not _pasture:
		_show_toast("Na lodowcu nie da się trzymać zwierząt.", UI.ERROR)
		return
	if not _animal_kinds.get(kind, {}).get("lives", true):
		_show_toast("Wielbłąd żyje tylko na pustyni i w oazie." if kind == "animal_camel" else "Na pustyni żyją tylko wielbłądy.", UI.ERROR)
		return
	_set_planting(false)
	_stop_placing()
	_stop_work()
	_inventory_window.hide_window()
	_releasing = kind
	var info: Dictionary = _animal_kinds.get(kind, {})
	if info.is_empty():
		_show_toast("Kliknij wolne pole, aby wypuścić: %s. Esc anuluje." % _item_name(kind).to_lower())
	else:
		var minutes := float(info["seconds"]) / 60.0
		_show_toast("Kliknij wolne pole, aby wypuścić: %s. Nakarmione zwierzę da %s w %s min. Esc anuluje." % [
			_item_name(kind).to_lower(), str(info["productName"]).to_lower(), str(snappedf(minutes, 0.1)).trim_suffix(".0").replace(".", ",")])
	_update_hint()


func _stop_releasing() -> void:
	_releasing = ""
	_update_hint()


func _release_animal(cell: Vector2i) -> void:
	if not _can_release(cell):
		return
	var kind := _releasing
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.release", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y, "item": kind})
	if reply["type"] != "plot.animal":
		_show_error(reply)
		return
	_apply_animal(reply, "−1 %s" % _item_name(kind))
	if _count(kind) <= 1:
		_stop_releasing()


## What an animal under the mouse is doing, and what a click does about it.
func _animal_label(cell: Vector2i) -> String:
	var animal: Dictionary = _animals[cell]
	var info: Dictionary = _animal_kinds.get(animal["kind"], {})
	var product: String = str(info.get("productName", "")).to_lower()
	if animal.get("readyAt") == null:
		return "%s: głodna, kliknij, aby nakarmić" % animal["name"]
	var left := _animal_left(cell)
	if left <= 0.0:
		var how := " (nożycami)" if info.get("tool") == "tool_shears" else ""
		return "%s: kliknij, aby zebrać: %s%s" % [animal["name"], product, how]
	return "%s: da %s za %d:%02d" % [animal["name"], product, ceili(left) / 60, ceili(left) % 60]


## Seconds until a fed animal gives its product (0 when it does).
func _animal_left(cell: Vector2i) -> float:
	var ready_at: Variant = _animals[cell].get("readyAt")
	return maxf((float(ready_at) - _server_now()) / 1000.0, 0.0) if ready_at != null else 0.0


func _animal_ready(cell: Vector2i) -> bool:
	return _animals.has(cell) and _animals[cell].get("readyAt") != null and _animal_left(cell) <= 0.0


## Feed (one entry per crop in the inventory), collect or take the animal; ids 0-99 feed, 100 collects, 101 takes.
func _open_animal_menu(cell: Vector2i) -> void:
	_menu_animal = cell
	_animal_menu.clear()
	var animal: Dictionary = _animals[cell]
	var info: Dictionary = _animal_kinds.get(animal["kind"], {})
	if _animal_ready(cell):
		var how := "  (nożyce w ręce)" if info.get("tool") == "tool_shears" else ""
		_animal_menu.add_icon_item(UI.texture("icons/item_" + str(info.get("product", "egg"))),
			"Zbierz: %s  ·  %d szt.%s" % [str(info.get("productName", "")).to_lower(), int(info.get("yield", 1)), how], 100)
	elif animal.get("readyAt") == null:
		var any := false
		for i in _feed.size():
			var feed: Dictionary = _feed[i]
			var have := _count(feed["id"])
			if have >= _feed_per_meal:
				any = true
				_animal_menu.add_icon_item(UI.texture("icons/item_" + str(feed["id"])), "Nakarm: %s × %d  (masz %d)" % [str(feed["name"]).to_lower(), _feed_per_meal, have], i)
		if not any:
			var names := PackedStringArray()
			for feed: Dictionary in _feed:
				names.append(str(feed["name"]).to_lower())
			_animal_menu.add_item("Nakarm: brak paszy (%d × %s)" % [_feed_per_meal, " / ".join(names)], 99)
			_animal_menu.set_item_disabled(_animal_menu.get_item_count() - 1, true)
	else:
		var left := ceili(_animal_left(cell))
		_animal_menu.add_item("%s za %d:%02d" % [str(info.get("productName", "")).capitalize(), left / 60, left % 60], 99)
		_animal_menu.set_item_disabled(_animal_menu.get_item_count() - 1, true)
	_animal_menu.add_item("Zabierz do ekwipunku", 101)
	_animal_menu.reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(12, 4)
	_animal_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_animal_chosen(choice: int) -> void:
	var cell := _menu_animal
	_menu_animal = Vector2i(-1, -1)
	if not _animals.has(cell):
		return
	if choice == 100:
		_go_and(cell, _collect_animal)
	elif choice == 101:
		_go_and(cell, _take_animal)
	elif choice < _feed.size():
		var feed: String = _feed[choice]["id"]
		_go_and(cell, func(at: Vector2i) -> void: _feed_animal(at, feed))


func _feed_animal(cell: Vector2i, feed: String) -> void:
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.feed", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y, "item": feed})
	if reply["type"] != "plot.animal":
		_show_error(reply)
		return
	_apply_animal(reply, "−%d %s" % [_feed_per_meal, _item_name(feed)])


func _collect_animal(cell: Vector2i) -> void:
	var info: Dictionary = _animal_kinds.get(_animals[cell]["kind"], {})
	if info.get("tool") != null and not Game.holds(info["tool"]):
		_show_toast("%s: potrzebujesz %s. Zmień narzędzie w slocie [Q]." % [_animals[cell]["name"], str(info.get("toolName", "")).to_lower()], UI.ERROR)
		return
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.collect", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] != "plot.animal":
		_show_error(reply)
		return
	_apply_animal(reply, "")


func _take_animal(cell: Vector2i) -> void:
	var reply := await Net.request("plot.takeAnimal", {"x": _at.x, "y": _at.y, "tileX": cell.x, "tileY": cell.y})
	if reply["type"] != "plot.animal":
		_show_error(reply)
		return
	_apply_animal(reply, "")


## Shows the server's answer to letting out, feeding, collecting from or taking an animal.
func _apply_animal(reply: Dictionary, spent: String) -> void:
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var cell := Vector2i(result["tileX"], result["tileY"])
	if result.get("animal") == null:
		_animals.erase(cell)
	else:
		_animals[cell] = result["animal"]
	if _hovered == cell and not _animals.has(cell):
		_hovered = Vector2i(-1, -1)
	_draw_cell(cell)
	var items: Array = result["items"]
	var shown := 0
	if spent != "":
		_float_text(spent, UI.MUTED, _cell_centre(cell), 0.0)
		shown += 1
	for item: Dictionary in items:
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, _cell_centre(cell), shown * 0.25, item["id"])
		shown += 1
	if result.get("xp") != null:
		var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
		if gained > 0:
			_float_text("+%d XP" % gained, UI.GOLD, _cell_centre(cell), shown * 0.25)
		Game.gain_xp(result["xp"])
		_refresh_character()
		if result["xp"].get("leveledUp", false):
			_show_toast("Awans! Poziom %d" % int(result["xp"]["level"]), UI.GOLD)
	_update_hint()
	if _inventory_window.visible or _station_window.visible or spent != "" or not items.is_empty():
		_reload_inventory()


# --- Workbench and furnace -------------------------------------------------------------------------

## Starts putting a workbench or furnace from the inventory on the plot: a click on free ground places it.
func _start_placing(kind: String) -> void:
	_set_planting(false)
	_stop_releasing()
	_stop_work()
	_inventory_window.hide_window()
	_placing = kind
	if kind in MACHINERY:
		_show_toast("Kliknij wolne pole, aby postawić: %s. [R] obraca, Esc kończy." % _item_name(kind).to_lower())
	else:
		_show_toast("Kliknij wolne pole, aby postawić: %s. Esc anuluje." % _item_name(kind))
	_update_hint()


func _stop_placing() -> void:
	_placing = ""
	_update_hint()


func _item_name(item: String) -> String:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return stack["name"]
	return item


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _place_object(cell: Vector2i) -> void:
	if not _can_place(cell) or _in_footprint(_placing, cell):
		if _placing == EXPORT_CHEST and not _by_station(cell):
			_show_toast("Skrzynia eksportowa stoi przy stacji: najwyżej %d pola od budynku albo toru." % EXPORT_REACH, UI.ERROR)
		else:
			_show_toast("Tu nie można tego postawić.", UI.ERROR)
		return
	var kind := _placing
	# Belts and inserters are laid one after another until they run out.
	var more := (kind in MACHINERY or kind == ROAD) and _count(kind) > 1
	if not more:
		_stop_placing()
	_player.face(Vector2(cell.x + 0.5 - _player.floor_pos.x, _player.floor_pos.y - cell.y - 0.5))
	var reply := await Net.request("plot.place", {"x": _at.x, "y": _at.y, "kind": kind, "tileX": cell.x, "tileY": cell.y, "rotation": _place_rotation})
	if reply["type"] != "plot.placed":
		_show_error(reply)
		return
	var object: Dictionary = reply["payload"]["object"]
	var at := Vector2i(object["tileX"], object["tileY"])
	_put_placed(object)
	for covered in _footprint(object["kind"], at):
		_astar.set_point_solid(covered, not _walkable(covered))
		_draw_cell(covered)
	_logistics.set_objects(_placed)
	_draw_tunnels()
	_update_market_button()
	_power.set_objects(_placed)
	if kind in MACHINERY:
		_show_toast("%s stoi %s. %s" % [object["name"], DIRECTIONS[int(object["rotation"])], "Kliknij kolejne pole albo Esc." if more else ""])
	elif kind == COMPUTER:
		_show_toast("%s stoi na działce. Kliknij go albo naciśnij [M], aby otworzyć rynek." % object["name"])
	elif FORESTERS.has(kind):
		_show_toast("%s stoi na działce i już sadzi las wokół siebie. Drewno wyjmiesz ręcznie albo podajnikiem." % object["name"])
		_poll_forestry()
	elif FARMSTEADS.has(kind):
		_show_toast("%s stoi na działce i już obsiewa pole wokół siebie. Plony wyjmiesz ręcznie albo podajnikiem." % object["name"])
		_poll_farmsteads()
	elif kind == EXPORT_CHEST:
		_show_toast("%s stoi przy stacji. Kliknij ją, ustaw ceny towarów, a pociąg co godzinę zawiezie je na rynek skupu." % object["name"])
	elif kind == BUY_MARKET:
		_show_toast("%s stoi w mieście. Pociągi z całego lądu przywiozą tu towar na rynek graczy; kliknij go, aby ustawić prowizję." % object["name"])
	elif kind == RAIL_PORT:
		_show_toast("%s stoi na brzegu: pociągi z eksportem przeprawią się stąd promem. Kliknij go, aby ustawić opłatę." % object["name"])
	elif kind == BANK:
		_show_toast("%s stoi w mieście: gracze otworzą w nim konta. Oddziały w innych miastach skrócą im drogę pieniędzy." % object["name"])
	elif kind == BANK_BRANCH:
		_show_toast("%s stoi w mieście: wpłaty i wypłaty graczy z okolicy pójdą teraz tędy, krótszą drogą." % object["name"])
	elif kind == CANTEEN:
		_show_toast("%s stoi na działce. Wydaj w niej jedzenie, a maszyny na opał i na prąd przyspieszą o 20%%." % object["name"])
	elif kind == STABLE:
		_show_toast("%s stoi na działce: teraz wypuścisz tu konia, a stacja wyśle wozy konne." % object["name"])
	elif kind == BELLOWS:
		_show_toast("%s stoi na działce: piece i odlewnia pracują tu o 15%% szybciej." % object["name"])
	elif kind in DRILLS:
		_show_toast("%s stoi przy kopalni. Podłącz je słupem do prądu, a samo zacznie wydobywać." % object["name"])
	elif kind in HYDRO:
		_show_toast("%s stoi na działce i daje prąd bez opału. Postaw obok słup energetyczny." % object["name"])
	elif kind in SOLAR:
		_show_toast("%s stoi na działce i za dnia daje prąd bez opału. Postaw obok słup, a nadwyżkę zbierze akumulator." % object["name"])
	elif kind == BATTERY:
		_show_toast("%s stoi na działce: postaw obok słup, a zbierze nadwyżkę prądu ze słońca i wody i odda ją, gdy zabraknie." % object["name"])
	elif kind in WIND:
		_show_toast("%s stoi na działce i daje prąd, gdy wieje. Postaw obok słup; w zamieć staje." % object["name"])
	elif kind == HEATER:
		_show_toast("%s stoi na działce: dołóż opału, a ogrzeje maszyny do 3 pól wokół, by nie marzły." % object["name"])
	elif kind == TRACK_FOUNDATION:
		_show_toast("%s leży na działce: pociągi przez lodowiec nie będą już zwalniać." % object["name"])
	elif kind == "furniture_dog_kennel" or kind == "furniture_snowmobile_garage":
		_show_toast("%s stoi na działce: w oknie stacji [T] wyślesz teraz towar saniami." % object["name"])
	elif kind in TOURISM:
		_show_toast("%s przyjmuje turystów. Utarg trafia prosto do portfela, a w noce z zorzą jest potrójny." % object["name"])
	elif kind == WATCHTOWER:
		_show_toast("%s stoi na działce: pożar lasu zobaczysz wcześnie, więc spłonie najwyżej %d pól wokół miejsca, gdzie wybuchł." % [object["name"],
			int(_plot.get("fires", {}).get("watchtowerRadius", 4))])
	elif kind == FIRE_STATION:
		_show_toast("%s stoi na działce: drzewa do %d pól wokół niej nigdy nie spłoną." % [object["name"], int(_plot.get("fires", {}).get("stationReach", 12))])
	elif kind == BEEHIVE:
		_show_toast("%s stoi na działce: pszczoły same robią miód i wosk, szybciej przy kwitnących lipach. Kliknij go, aby wybrać miód." % object["name"])
	elif kind == REED_FENCE:
		_show_toast("%s stoi na działce: osłoni przed burzą piaskową panele 3 pola wokół i wykopane wydmy 4 pola wokół." % object["name"])
	elif kind in WELLS:
		_show_toast("%s stoi na złożu i sam pompuje%s. Wyjmij urobek w jego oknie albo pompą do rury." % [object["name"],
			", gdy podłączysz go słupem do prądu" if _power.runs_on_power(kind) else ""])
	else:
		_show_toast("%s stoi na działce. Kliknij, aby użyć." % object["name"])
	_reload_inventory()
	_poll_logistics()


## The placed object next to the player, or (-1, -1).
func _nearest_placed() -> Vector2i:
	for cell: Vector2i in _placed:
		if _near(cell) and not _turnable(cell) and not _placed[cell]["kind"] in MENU_ONLY:
			return cell
	return Vector2i(-1, -1)


func _use_placed(cell: Vector2i) -> void:
	if not _placed.has(cell):
		return
	var object: Dictionary = _placed[cell]
	_using = cell
	_station_window.hide_window()
	_hide_placed_windows()
	if object["kind"] == COMPUTER:
		# The market stays open while the player walks around the plot.
		_using = Vector2i(-1, -1)
		_market_window.open_at(object["id"])
	elif object["kind"] in FURNACES:
		_furnace_window.open_at(object["id"])
		_offer_filter(_furnace_window, object, "machine")
	elif object["kind"] in MACHINES:
		_machine_window.open_at(object["id"], object["name"])
		_offer_filter(_machine_window, object, "machine")
	elif object["kind"] in STORAGES:
		_storage_window.open_at(_at, object["id"])
		_offer_filter(_storage_window, object, "storage")
	elif object["kind"] in ["furniture_workbench", "furniture_anvil", SHIPYARD, "furniture_tailor"]:
		_crafting_window.open_at(object["id"], object["kind"])
	elif object["kind"] == ResearchWindow.TABLE:
		_research_window.open_at(object["id"])
	elif object["kind"] in GENERATORS or object["kind"] in HYDRO or object["kind"] in SOLAR or object["kind"] == BATTERY \
			or object["kind"] in WIND or object["kind"] == HEATER:
		_generator_window.open_at(_at, object["id"])
		# Only generators that burn fuel take anything in.
		if object["kind"] in GENERATORS:
			_offer_filter(_generator_window, object, "machine")
		else:
			_generator_window.hide_filter_button()
	elif object["kind"] in WELLS:
		_well_window.open_at(_at, object["id"])
	elif object["kind"] == SHOP:
		_shop_window.open_at(object["id"])
	elif object["kind"] == BEEHIVE:
		_hive_window.open_at(object["id"])
	elif object["kind"] in DRILLS:
		_drill_window.open_at(_at, object["id"])
	elif FORESTERS.has(object["kind"]):
		_forester_window.open_at(_at, object["id"])
	elif FARMSTEADS.has(object["kind"]):
		_farmstead_window.open_at(_at, object["id"])
	elif object["kind"] == CANTEEN:
		_canteen_window.open_at(object["id"])
	elif object["kind"] == EXPORT_CHEST:
		_export_window.open_at(_at)
	elif object["kind"] in [BUY_MARKET, RAIL_PORT]:
		_export_post_window.open_at(object["id"])
	elif object["kind"] in [BANK, BANK_BRANCH]:
		_open_bank_of(object["id"])


## Opens the page of the bank a building on the plot belongs to.
func _open_bank_of(id: String) -> void:
	var reply := await Net.request("bank.building", {"id": id})
	if reply["type"] != "bank.building":
		_show_error(reply)
		return
	_bank_window.open_bank(str(reply["payload"]["bank"]))


func _using_window_open() -> bool:
	return _crafting_window.visible or _research_window.visible or _furnace_window.visible or _machine_window.visible or _storage_window.visible \
		or _splitter_window.visible or _filter_window.visible or _generator_window.visible or _market_window.visible or _forester_window.visible \
		or _farmstead_window.visible or _canteen_window.visible \
		or _drill_window.visible or _well_window.visible or _shop_window.visible or _hive_window.visible \
		or _export_window.visible or _export_post_window.visible


func _hide_placed_windows() -> void:
	_crafting_window.hide_window()
	_research_window.hide_window()
	_furnace_window.hide_window()
	_machine_window.hide_window()
	_forester_window.hide_window()
	_farmstead_window.hide_window()
	_canteen_window.hide_window()
	_generator_window.hide_window()
	_drill_window.hide_window()
	_well_window.hide_window()
	_shop_window.hide_window()
	_hive_window.hide_window()
	_export_window.hide_window()
	_export_post_window.hide_window()
	_storage_window.hide_window()
	_splitter_window.hide_window()
	_filter_window.hide_window()
	_market_window.hide_window()


## The first computer on the plot, or (-1, -1) when there is none.
func _computer() -> Vector2i:
	for cell: Vector2i in _placed:
		if _placed[cell]["kind"] == COMPUTER:
			return cell
	return Vector2i(-1, -1)


## [M] and the bar's button: with a computer anywhere on the plot the market opens wherever the player is.
func _toggle_market() -> void:
	if _market_window.visible:
		_market_window.hide_window()
		return
	var cell := _computer()
	if cell.x < 0:
		_show_toast("Rynek na działce działa przy komputerze. Kupisz go u handlarza w garażu i postawisz tutaj.", UI.MUTED)
		return
	_use_placed(cell)


func _update_market_button() -> void:
	_market_button.visible = _computer().x >= 0


## After any trade in the market window: new balance and inventory.
func _on_traded(balance_cents: int, _item: String) -> void:
	_set_balance(balance_cents)
	await _reload_inventory()
	_market_window.refresh()


func _pick_up_placed(id: String) -> void:
	var reply := await Net.request("plot.pickup", {"x": _at.x, "y": _at.y, "id": id})
	if reply["type"] != "plot.pickedUp":
		_show_error(reply)
		return
	var shown := false
	var forester := _foresters.has(id)
	_foresters.erase(id)
	var farm := _farmsteads.has(id)
	_farmsteads.erase(id)
	for cell: Vector2i in _placed.keys():
		if _placed[cell]["id"] == id:
			if not shown:
				_show_toast("%s: schowano do ekwipunku%s." % [_placed[cell]["name"], ", a z nim jego las" if forester else ", a z nią jej pola" if farm else ""])
				shown = true
			_placed.erase(cell)
			_astar.set_point_solid(cell, _tile(cell) in SOLID)
			if _hovered == cell:
				_hovered = Vector2i(-1, -1)
			_draw_cell(cell)
	_logistics.set_objects(_placed)
	_draw_tunnels()
	_power.set_objects(_placed)
	_hide_placed_windows()
	_update_market_button()
	_using = Vector2i(-1, -1)
	_reload_inventory()
	_poll_logistics()
	if forester:
		# Its forest went with it: the trees it planted are gone from the plot.
		_poll_forestry()
	if farm:
		_poll_farmsteads()


# --- Holding an object to put it away -------------------------------------------------------

## Starts holding the object under the mouse (if it is a placed one) with `button`.
func _start_hold(button: MouseButton) -> void:
	_hold_button = button
	_hold_id = _held_id()
	_hold_from = get_viewport().get_mouse_position()
	_hold_for = 0.0


func _stop_hold() -> void:
	if _hold_id != "":
		_hold_id = ""
		_marks.queue_redraw()


## The id of the placed object under the mouse, or "" when there is none (or the mouse is over the interface).
func _held_id() -> String:
	if _placing != "" or _releasing != "":
		return ""
	return str(_placed[_hovered]["id"]) if _placed.has(_hovered) else ""


## Counts the hold up, calls it off when the button is let go or the mouse leaves the object, and puts the
## object away once it was held long enough.
func _update_hold(delta: float) -> void:
	if _hold_id == "":
		return
	var finger := _hold_button == MOUSE_BUTTON_LEFT
	var slipped := get_viewport().get_mouse_position().distance_to(_hold_from) > HOLD_SLIP
	# The character walks after a tap and the plot slides under the finger, so a finger only has to stay put.
	var left := slipped if finger else _held_id() != _hold_id
	if not Input.is_mouse_button_pressed(_hold_button) or left or (finger and _touches.size() > 1):
		_stop_hold()
		return
	_hold_for += delta
	_marks.queue_redraw()
	if _hold_for < HOLD_TO_PICK_UP:
		return
	var id := _hold_id
	_stop_hold()
	var cell := _placed_cell(id)
	if cell.x < 0:
		return
	# Whatever the tap opened goes away: the object itself does.
	_object_menu.hide()
	_menu_object = Vector2i(-1, -1)
	_hide_placed_windows()
	_go_and(cell, func(at: Vector2i) -> void:
		if _placed.has(at) and _placed[at]["id"] == id:
			_pick_up_placed(id))


## A tile of the placed object with this id, or (-1, -1) when it is gone.
func _placed_cell(id: String) -> Vector2i:
	for cell: Vector2i in _placed:
		if _placed[cell]["id"] == id:
			return cell
	return Vector2i(-1, -1)


## The ring filling up around the object being held.
func _draw_hold() -> void:
	var cell := _placed_cell(_hold_id)
	if cell.x < 0:
		return
	var kind: String = _placed[cell]["kind"]
	var size := _ring_size(kind) * 1.15
	var at := _object_centre(kind, _anchor(cell)) if _big(kind) else _cell_centre(cell)
	var part := clampf(_hold_for / HOLD_TO_PICK_UP, 0.0, 1.0)
	_marks.draw_set_transform(at, 0, Vector2(1, TILE.y / TILE.x))
	_marks.draw_arc(Vector2.ZERO, TILE.x * 0.55 * size, 0, TAU, 40, Color(0.05, 0.05, 0.06, 0.45), 6.0, true)
	if part > 0.0:
		_marks.draw_arc(Vector2.ZERO, TILE.x * 0.55 * size, -PI / 2, -PI / 2 + TAU * part, 40, Color(0.96, 0.69, 0.25, 0.95), 6.0, true)
	_marks.draw_set_transform(Vector2.ZERO)


func _open_object_menu(cell: Vector2i) -> void:
	_menu_object = cell
	_object_menu.clear()
	if _turnable(cell):
		_object_menu.add_item("Obróć  [R]", 0)
	_object_menu.add_item("Schowaj do ekwipunku", 1)
	if _placed.has(cell) and _placed[cell]["kind"] == SPLITTER:
		_object_menu.add_item("Ustaw, co idzie w którą stronę", 2)
	if _placed.has(cell) and _placed[cell]["kind"] in INSERTERS:
		var only := _logistics.filter(_placed[cell]["id"])
		if only != "":
			_object_menu.add_icon_item(UI.item_texture(only), "Filtr: %s (zmień)" % _filter_name(only).to_lower(), 3)
			_object_menu.set_item_icon_max_width(_object_menu.get_item_count() - 1, 20)
		else:
			_object_menu.add_item("Ustaw filtr", 3)
	_object_menu.reset_size()
	var at := get_viewport().get_mouse_position() + Vector2(12, 4)
	_object_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_object_chosen(choice: int) -> void:
	var cell := _menu_object
	_menu_object = Vector2i(-1, -1)
	if not _placed.has(cell):
		return
	if choice == 0:
		_rotate_placed(cell)
	elif choice == 2:
		_open_splitter(cell)
	elif choice == 3:
		_open_filter(_placed[cell], "inserter")
	else:
		_go_and(cell, func(at: Vector2i) -> void:
			if _placed.has(at):
				_pick_up_placed(_placed[at]["id"]))


func _open_splitter(cell: Vector2i) -> void:
	var object: Dictionary = _placed[cell]
	_hide_placed_windows()
	_splitter_window.names = _logistics.names
	_splitter_window.set_items(_items)
	_splitter_window.open_at(_at, object["id"], int(object.get("rotation", 0)), _logistics.splitter(object["id"]))


## Opens the filter of an inserter, a storage or a machine (`role` says which).
func _open_filter(object: Dictionary, role: String) -> void:
	if role == "inserter":
		_hide_placed_windows()
	elif not UI.touch():
		# Beside the window of the storage or machine; on a phone, over it, as it would not fit beside.
		_filter_window.position = Vector2(maxf(12.0, get_viewport_rect().size.x - 2 * 412.0), 64)
	_filter_window.names = _logistics.names
	_filter_window.set_items(_items)
	var allowed: Array = []
	var only: Variant = _logistics.storage(object["id"]).get("only")
	if only != null:
		allowed = (only as Array).map(func(i: Dictionary) -> String: return i["id"])
	_filter_window.open_at(_at, object["id"], object["name"], _logistics.filter(object["id"]), role, allowed)
	if _filter_window.names.is_empty():
		# Names come with the plot's logistics when asked for.
		var reply := await Net.request("logistics.get", {"x": _at.x, "y": _at.y, "names": true})
		if reply["type"] == "logistics":
			_logistics.apply(reply["payload"])
			_filter_window.names = _logistics.names
			_filter_window.set_items(_items)


## The "Filtr" button on the title bar of the window of a storage or a machine that can have a filter.
func _offer_filter(window: GameWindow, object: Dictionary, role: String) -> void:
	window.show_filter_button(_logistics.filter(object["id"]), func() -> void: _open_filter(object, role))


func _on_filters_changed() -> void:
	_filter_marks.queue_redraw()
	# The filter button of the open window shows the item set now.
	for window: GameWindow in [_storage_window, _furnace_window, _machine_window, _generator_window]:
		if window.visible and window.has_filter_button() and _using.x >= 0 and _placed.has(_using):
			_offer_filter(window, _placed[_using], "storage" if window == _storage_window else "machine")


## A small icon of the filtered item on each object with a filter: on its own tile, raised onto its front.
func _draw_filters() -> void:
	var filters := _logistics.filters()
	if filters.is_empty():
		return
	var drawn := {}
	for cell: Vector2i in _placed:
		var object: Dictionary = _placed[cell]
		if not filters.has(object["id"]) or drawn.has(object["id"]) or _anchor(cell) != cell:
			continue
		drawn[object["id"]] = true
		var lift := 0.35 if object["kind"] in INSERTERS else 0.3 + 0.5 * Footprints.size(object["kind"])
		var at := _object_centre(object["kind"], cell) - Vector2(0, TILE.y * lift)
		_filter_marks.draw_circle(at, 12.0, Color(0.09, 0.08, 0.07, 0.85))
		_filter_marks.draw_arc(at, 12.0, 0, TAU, 24, Color(0.96, 0.69, 0.25, 0.95), 1.5, true)
		_filter_marks.draw_texture_rect(_logistics._icon(filters[object["id"]]), Rect2(at - Vector2(8, 8), Vector2(16, 16)), false)


## Turns a belt or inserter a quarter turn anticlockwise: south, east, north, west.
func _rotate_placed(cell: Vector2i) -> void:
	var object: Dictionary = _placed[cell]
	var reply := await Net.request("plot.rotate", {"x": _at.x, "y": _at.y, "id": object["id"], "rotation": (int(object.get("rotation", 0)) + 1) % 4})
	if reply["type"] != "plot.rotated":
		_show_error(reply)
		return
	_placed[cell] = reply["payload"]["object"]
	_logistics.set_objects(_placed)
	_draw_tunnels()
	_power.set_objects(_placed)
	_draw_cell(cell)
	_poll_logistics()


## Asks for the belts, inserters and storage as the server has them now.
func _poll_logistics() -> void:
	if _polling_logistics:
		return
	_polling_logistics = true
	_next_logistics_poll = Time.get_ticks_msec() + LOGISTICS_POLL
	# Item names once, for choosing filters.
	var reply := await Net.request("logistics.get", {"x": _at.x, "y": _at.y, "names": _logistics.names.is_empty()})
	_polling_logistics = false
	if reply["type"] == "logistics":
		_logistics.apply(reply["payload"])
		_power.apply(reply["payload"].get("power", {}))


func _has_foresters() -> bool:
	for cell: Vector2i in _placed:
		if FORESTERS.has(_placed[cell]["kind"]):
			return true
	return false


## Asks for the foresters and the trees of the plot as the server has them now.
func _poll_forestry() -> void:
	if _polling_forestry:
		return
	_polling_forestry = true
	_next_forestry_poll = Time.get_ticks_msec() + FORESTRY_POLL
	var reply := await Net.request("forestry.get", {"x": _at.x, "y": _at.y})
	_polling_forestry = false
	if reply["type"] == "forestry":
		_apply_forestry(reply["payload"])


## Draws what the foresters did: saplings planted on free tiles, grown trees felled and planted again.
func _apply_forestry(forestry: Dictionary) -> void:
	_clock_offset = float(forestry["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_foresters = {}
	for forester: Dictionary in forestry.get("foresters", []):
		_foresters[forester["id"]] = forester
	var seen := {}
	for tree: Dictionary in forestry.get("trees", []):
		var cell := Vector2i(tree["tileX"], tree["tileY"])
		seen[cell] = true
		if _trees.has(cell) and float(_trees[cell]) == float(tree["readyAt"]):
			continue
		var felled := _trees.has(cell) and _tree_grown(cell) and float(tree["readyAt"]) > _server_now()
		var sprite := _sprite_at(cell) if felled else ""
		_trees[cell] = tree["readyAt"]
		_tree_species[cell] = tree.get("species", "pine")
		if _hovered == cell:
			_hovered = Vector2i(-1, -1)
		_draw_cell(cell)
		_set_minimap(cell, NONE)
		if felled and _chunks.has(Vector2i(cell.x / CHUNK, cell.y / CHUNK)):
			_vanish(sprite, cell, true)
	for cell: Vector2i in _trees.keys():
		if not seen.has(cell):
			_trees.erase(cell)
			_draw_cell(cell)
	# Trees that grew here by themselves, cut by a forester.
	for tile: Dictionary in forestry.get("cleared", []):
		var cell := Vector2i(tile["tileX"], tile["tileY"])
		if _tile(cell) in TREES:
			var wild := _variant(_tile(cell), cell)
			_tiles[cell.y * _size + cell.x] = NONE
			_astar.set_point_solid(cell, _placed.has(cell) and not _walkable(cell))
			if _chunks.has(Vector2i(cell.x / CHUNK, cell.y / CHUNK)) and not _trees.has(cell):
				_vanish(wild, cell, true)
			_draw_cell(cell)
	if _forester_window.visible:
		_forester_window.show_state(forestry)


func _has_farmsteads() -> bool:
	for cell: Vector2i in _placed:
		if FARMSTEADS.has(_placed[cell]["kind"]):
			return true
	return false


## Asks for the farmsteads and the fields they sow as the server has them now.
func _poll_farmsteads() -> void:
	if _polling_farms:
		return
	_polling_farms = true
	_next_farm_poll = Time.get_ticks_msec() + FORESTRY_POLL
	var reply := await Net.request("farmstead.get", {"x": _at.x, "y": _at.y})
	_polling_farms = false
	if reply["type"] == "farmsteads":
		_apply_farmsteads(reply["payload"])


## Draws what the farmsteads did: fields tilled and sown, ripe ones reaped and sown again.
func _apply_farmsteads(farms: Dictionary) -> void:
	_clock_offset = float(farms["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_farmsteads = {}
	for farm: Dictionary in farms.get("farmsteads", []):
		_farmsteads[farm["id"]] = farm
	var seen := {}
	for field: Dictionary in farms.get("fields", []):
		var cell := Vector2i(field["tileX"], field["tileY"])
		seen[cell] = true
		var known: Dictionary = _fields.get(cell, {})
		if not known.is_empty() and known["crop"] == field["crop"] and known["readyAt"] != null and float(known["readyAt"]) == float(field["readyAt"]):
			continue
		_fields[cell] = {"crop": field["crop"], "readyAt": field["readyAt"]}
		if _hovered == cell:
			_hovered = Vector2i(-1, -1)
		_draw_cell(cell)
	# Fields of a farmstead picked up go with it.
	for cell: Vector2i in _farm_fields.keys():
		if not seen.has(cell):
			_fields.erase(cell)
			_draw_cell(cell)
	_farm_fields = seen
	if _farmstead_window.visible:
		_farmstead_window.show_state(farms)


## Orders from a workbench are done: they are in the inventory now.
func _on_crafted(done: Array, xp: Variant) -> void:
	var at := _cell_centre(_using) if _using.x >= 0 else _player.position
	for i in done.size():
		var item: Dictionary = done[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, at, i * 0.25, item["id"])
	_gain(xp, at, done.size() * 0.25)
	_show_toast("Gotowe: %s. Leży w ekwipunku." % ", ".join(done.map(func(item: Dictionary) -> String: return item["name"])))
	_reload_inventory()


func _on_researched(finished: Array, xp: Variant) -> void:
	_gain(xp, _player.position, 0.0)
	_show_toast("Zbadano: %s. Nowe przepisy czekają przy stole." % ", ".join(finished.map(func(t: Dictionary) -> String: return t["name"])), UI.GOOD)
	# The workbench shows the recipes the research unlocked.
	_crafting_window.refresh()


func _on_furnace_changed(taken: Array, xp: Variant) -> void:
	var at := _cell_centre(_using) if _using.x >= 0 else _player.position
	for i in taken.size():
		var item: Dictionary = taken[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, at, i * 0.25, item["id"])
	_gain(xp, at, taken.size() * 0.25)
	_reload_inventory()
	# Tourists' takings go straight to the wallet.
	if taken.any(func(item: Dictionary) -> bool: return item["id"] in ["tourist_takings", "dining_takings"]):
		_reload_balance()


func _gain(xp: Variant, at: Vector2, delay: float) -> void:
	if xp == null:
		return
	var gained := int(xp["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, at, delay)
	Game.gain_xp(xp)
	_refresh_character()
	if xp.get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(xp["level"]), UI.GOLD)


# --- Mining --------------------------------------------------------------------------------------

## Puts a mine on its tiles, with the middle of its south edge as anchor like the station.
func _add_mine(mine: Dictionary) -> void:
	var foot := Vector2((int(mine["x"]) + int(mine["width"]) / 2.0) * TILE.x, (int(mine["y"]) + int(mine["height"])) * TILE.y)
	var anchor := Vector2(_layout["mine"]["anchorX"], _layout["mine"]["anchorY"])
	var sprite := Sprite2D.new()
	sprite.texture = load("res://art/plot/mine.png")
	sprite.centered = false
	sprite.offset = -anchor
	sprite.position = foot
	_sorted.add_child(sprite)
	var shadow := Sprite2D.new()
	shadow.texture = load("res://art/plot/mine_shadow.png")
	shadow.centered = false
	shadow.offset = -anchor
	shadow.position = foot
	_shadows.add_child(shadow)
	if not _images.has("mine"):
		_images["mine"] = sprite.texture.get_image()
	var state := mine.duplicate()
	state["sprite"] = sprite
	_mines[int(mine["id"])] = state


## The mine drawn under a point of the world, or -1.
func _mine_at(point: Vector2) -> int:
	for id: int in _mines:
		var sprite: Sprite2D = _mines[id]["sprite"]
		var pixel := Vector2i(point - sprite.position - sprite.offset)
		var image: Image = _images["mine"]
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel) and image.get_pixelv(pixel).a > 0.4:
			return id
	return -1


func _mine_rect(id: int) -> Rect2:
	var mine: Dictionary = _mines[id]
	return Rect2(mine["x"], mine["y"], mine["width"], mine["height"])


func _near_mine(id: int) -> bool:
	var r := _mine_rect(id)
	var p := _player.floor_pos
	return p.distance_to(p.clamp(r.position, r.end)) <= STATION_REACH


## The mine the player stands at, or -1.
func _nearest_mine() -> int:
	for id: int in _mines:
		if _near_mine(id):
			return id
	return -1


## Loads a mine has left now; a worked-out mine is full again once its rest is over.
func _mine_left_units(id: int) -> int:
	var mine: Dictionary = _mines[id]
	if mine["refillAt"] != null and _server_now() >= float(mine["refillAt"]):
		mine["units"] = int(mine.get("capacity", _mine_units))
		mine["refillAt"] = null
	return int(mine["units"])


## Seconds until a worked-out mine is full again.
func _mine_refill_left(id: int) -> int:
	var refill: Variant = _mines[id]["refillAt"]
	return ceili(maxf((float(refill) - _server_now()) / 1000.0, 0.0)) if refill != null else 0


func _update_mine_label(id: int) -> void:
	_field_label.visible = _menu_cell.x < 0
	if _mine_left_units(id) > 0:
		_field_label.text = "Kopalnia (poziom %d): %d/%d jednostek, kliknij, aby wydobywać kilofem" % [
			int(_mines[id].get("level", 1)), _mine_left_units(id), _mine_capacity(id)]
	else:
		var left := _mine_refill_left(id)
		_field_label.text = "Kopalnia wyczerpana: odnowi się za %d:%02d" % [left / 60, left % 60]
	_field_label.reset_size()
	# Over the entrance, kept on screen when the mine stands at its top edge.
	var foot: Vector2 = _mines[id]["sprite"].position
	_field_label.position = _screen(foot) - Vector2(_field_label.size.x / 2, 150 * _zoom)
	_field_label.position.y = maxf(_field_label.position.y, 130.0)


## Walks to the entrance of a mine and starts mining with the pickaxe.
func _go_to_mine(id: int) -> void:
	if not _holds("tool_pickaxe"):
		_show_toast("Kopalnia: potrzebujesz kilofa. Zmień narzędzie w slocie [Q].", UI.ERROR)
		return
	if _mine_left_units(id) <= 0:
		var left := _mine_refill_left(id)
		_show_toast("Kopalnia wyczerpana, odnowi się za %d:%02d." % [left / 60, left % 60], UI.MUTED)
		return
	_stop_work()
	if _near_mine(id):
		_start_mining(id)
		return
	var r := _mine_rect(id)
	var entrance := Vector2i(int(r.get_center().x), int(r.end.y))
	_walk_to(entrance, func() -> void:
		if _near_mine(id):
			_start_mining(id)
		else:
			_show_toast("Nie da się tam podejść.", UI.ERROR))


func _start_mining(id: int) -> void:
	# A mine built up takes less time a load.
	_mine_seconds = float(_mines[id].get("seconds", _mine_seconds))
	var r := _mine_rect(id)
	_start_work(Vector2i(int(r.get_center().x), int(r.end.y) - 1), "mine")
	_work_mine = id


## One load of ore (or five at once with dynamite); the player keeps mining while standing at the
## mine until it runs dry.
func _mine_request(id: int, blast := false) -> void:
	var reply := await Net.request("plot.blast" if blast else "plot.mine", {"x": _at.x, "y": _at.y, "mine": id})
	if reply["type"] != "plot.mined":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_clock_offset = float(result["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var state: Dictionary = result["mine"]
	_set_mine_state(id, state)
	var r := _mine_rect(id)
	var at := Vector2(r.get_center().x, r.end.y - 1.0) * TILE
	var items: Array = result["items"]
	if blast:
		_float_text("BUM! %d urobków" % int(result.get("blasted", 5)), UI.GOLD, at - Vector2(0, 20))
		_reload_inventory()
	if items.is_empty():
		_float_text("Pusto, tym razem nic", UI.MUTED, at)
	for i in items.size():
		var item: Dictionary = items[i]
		_float_text("+%d %s" % [int(item["quantity"]), item["name"]], UI.TEXT, at, i * 0.25, item["id"])
	var gained := int(result["xp"]["xp"]) - int(Game.character.get("xp", 0))
	if gained > 0:
		_float_text("+%d XP" % gained, UI.GOLD, at, maxi(items.size(), 1) * 0.25)
	Game.gain_xp(result["xp"])
	_refresh_character()
	if result["xp"].get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(result["xp"]["level"]), UI.GOLD)
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()
	if int(state["units"]) <= 0:
		_show_toast("Kopalnia wyczerpana. Odnowi się za %d min." % roundi(_mine_refill_left(id) / 60.0), UI.MUTED)
	elif not blast and _work.x < 0 and _path.is_empty() and _near_mine(id) and _holds("tool_pickaxe"):
		_start_mining(id)


func _mine_capacity(id: int) -> int:
	return int(_mines[id].get("capacity", _mine_units))


## Takes what the server says of a mine, keeping its sprite.
func _set_mine_state(id: int, state: Dictionary) -> void:
	for key: String in state:
		_mines[id][key] = state[key]
	if _mine_open == id and _mine_window.visible:
		_render_mine_window()


## Opens or closes the window of the mine the player stands at, where it is built up.
func _toggle_mine_window() -> void:
	if _mine_window.visible:
		_mine_window.hide_window()
		return
	var id := _nearest_mine()
	if id < 0:
		_show_toast("Podejdź do kopalni, aby ją rozbudować.", UI.MUTED)
		return
	_mine_open = id
	_render_mine_window()
	_mine_window.show_window()
	_reload_inventory()


## Seconds as players read them: 10, or 2,5 with a decimal comma.
static func _decimal(value: float) -> String:
	return "%d" % int(value) if is_equal_approx(value, roundf(value)) else ("%.1f" % value).replace(".", ",")


func _mine_level_text(level: Dictionary) -> String:
	return "%d jednostek, %s s na jednostkę, odnawia się po %s min" % [
		int(level["capacity"]), _decimal(float(level["seconds"])), _decimal(float(level["refillSeconds"]) / 60.0)]


func _render_mine_window() -> void:
	if not _mines.has(_mine_open):
		return
	UI.clear(_mine_box)
	var mine: Dictionary = _mines[_mine_open]
	_mine_window.set_title("Kopalnia, poziom %d" % int(mine.get("level", 1)))
	_mine_box.add_child(UI.label("Teraz: %s." % _mine_level_text(mine), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	if int(mine.get("rare", 1)) > 1:
		_mine_box.add_child(UI.label("Głęboka kopalnia: srebro i złoto trafiają się %d razy częściej." % int(mine["rare"]), UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
	if int(_plot.get("miningBonus", 0)) > 0:
		_mine_box.add_child(UI.label("W górach kopie się o %d%% szybciej. Kilof z brązu i stalowy przyspieszają jeszcze bardziej." % int(_plot["miningBonus"]), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var dynamite := _count("dynamite")
	var blast_row := HBoxContainer.new()
	blast_row.add_theme_constant_override("separation", 6)
	blast_row.add_child(UI.item_icon("dynamite", 26))
	var blast_label := UI.label("Dynamit: %d. Jedna laska wydobywa 5 urobków naraz." % dynamite, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	blast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blast_row.add_child(blast_label)
	var blast := UI.button("Wysadź", func() -> void:
		await _mine_request(_mine_open, true)
		_render_mine_window(), true)
	blast.disabled = dynamite == 0 or _mine_left_units(_mine_open) <= 0
	blast.tooltip_text = "Dynamit zrobisz przy stole warsztatowym z siarki, węgla i piasku (technologia „Materiały wybuchowe”)" if dynamite == 0 else ""
	blast_row.add_child(blast)
	_mine_box.add_child(blast_row)
	var drill := _drill_at(_mine_open)
	if drill.x >= 0:
		_mine_box.add_child(UI.label("Przy kopalni pracuje %s: kopie razem z tobą." % String(_placed[drill]["name"]).to_lower(), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var next: Variant = mine.get("upgrade")
	if next == null:
		_mine_box.add_child(UI.label("Kopalnia jest rozbudowana do końca.", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	_mine_box.add_child(HSeparator.new())
	_mine_box.add_child(UI.label("Poziom %d: %s." % [int(next["level"]), _mine_level_text(next)], UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
	_mine_box.add_child(UI.label("Potrzebne materiały:", UI.MUTED))
	var enough := true
	for cost: Dictionary in next["cost"]:
		var owned := _count(cost["id"])
		var need := int(cost["quantity"])
		enough = enough and owned >= need
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(cost["id"], 26))
		var name_label := UI.label(cost["name"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UI.label("%d/%d" % [need, owned], UI.GOOD if owned >= need else UI.ERROR, HORIZONTAL_ALIGNMENT_RIGHT))
		_mine_box.add_child(row)
	var button := UI.button("Rozbuduj do poziomu %d" % int(next["level"]), _upgrade_mine.bind(_mine_open), true)
	button.disabled = not enough
	if not enough:
		button.tooltip_text = "Brakuje materiałów. Sztabki przetopisz w piecu, drewno zetniesz siekierą." if int(next["level"]) <= 3 \
			else "Brakuje materiałów. Obudowę górniczą zrobisz przy stole warsztatowym (technologia „Głębokie górnictwo”), brąz i stal w odlewni."
	_mine_box.add_child(button)


func _upgrade_mine(id: int) -> void:
	var reply := await Net.request("plot.upgradeMine", {"x": _at.x, "y": _at.y, "mine": id})
	if reply["type"] != "plot.mineUpgraded":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_set_mine_state(id, result["mine"])
	Game.gain_xp(result["xp"])
	_refresh_character()
	_show_toast("Kopalnia rozbudowana do poziomu %d!" % int(result["mine"]["level"]), UI.GOLD)
	if result["xp"].get("leveledUp", false):
		_show_toast("Awans! Poziom %d" % int(result["xp"]["level"]), UI.GOLD)
	_reload_inventory()


# --- Station -------------------------------------------------------------------------------------

func _station_rect() -> Rect2:
	var s: Dictionary = _plot["station"]
	return Rect2(s["x"], s["y"], s["width"], s["height"])


func _near_station() -> bool:
	if _plot.is_empty():
		return false
	var r := _station_rect()
	var p := _player.floor_pos
	return p.distance_to(p.clamp(r.position, r.end)) <= STATION_REACH


func _go_to_station() -> void:
	if _plot.is_empty():
		return
	var open := func() -> void:
		_station_window.show_window()
		_refresh_station()
	if _near_station():
		open.call()
		return
	var r := _station_rect()
	var door := Vector2i(int(r.get_center().x), int(r.end.y) + 1)
	_walk_to(door, func() -> void:
		if _near_station():
			open.call())


# --- Every frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _ready_to_play:
		return
	_move_player(delta)
	_update_chunks()
	_update_fade()
	_camera.position = _player.position
	_update_hover()
	_update_hold(delta)
	_update_work(delta)
	_update_minimap_dot()
	_update_stages()
	_update_weather()
	if _station_window.visible and not _near_station():
		_station_window.hide_window()
	var at_mine := _nearest_mine()
	_mine_button.visible = at_mine >= 0
	if _mine_window.visible and at_mine != _mine_open:
		_mine_window.hide_window()
	if _using.x >= 0 and (not _placed.has(_using) or not _near(_using, REACH + 1.5)):
		_hide_placed_windows()
		_using = Vector2i(-1, -1)
	if (_logistics.has_machinery() or _power.has_power()) and Time.get_ticks_msec() >= _next_logistics_poll:
		_poll_logistics()
	if _has_foresters() and Time.get_ticks_msec() >= _next_forestry_poll:
		_poll_forestry()
	if (_has_farmsteads() or not _farm_fields.is_empty()) and Time.get_ticks_msec() >= _next_farm_poll:
		_poll_farmsteads()
	_poll_station()
	if Time.get_ticks_msec() >= _next_presence_poll:
		_poll_presence()


## Says where the player stands and shows the other players on the plot.
func _poll_presence() -> void:
	if _polling_presence:
		return
	_polling_presence = true
	_next_presence_poll = Time.get_ticks_msec() + PRESENCE_POLL
	var reply := await Net.request("plot.presence", {
		"x": _at.x, "y": _at.y,
		"posX": snappedf(_player.floor_pos.x, 0.01), "posY": snappedf(_player.floor_pos.y, 0.01),
		"facing": _player.facing, "walking": _player.walking,
	})
	_polling_presence = false
	if reply["type"] == "plot.presence":
		var players: Array = reply["payload"].get("players", [])
		_others.apply(players)
		if players.is_empty():
			# Alone on the plot: nobody needs to see this player walk, so asking less often is enough to notice someone coming.
			_next_presence_poll = Time.get_ticks_msec() + PRESENCE_POLL_ALONE
	elif reply["type"] == "error":
		_others.clear()
		# Not allowed here (any more), or the connection dropped: try again in a while.
		_next_presence_poll = Time.get_ticks_msec() + 3000.0


## Once a second: whether a storm keeps the boats ashore now, or when the next one comes; on sand,
## the sandstorm instead; everywhere, the light of the sun, which solar panels work by.
func _update_weather() -> void:
	_daylight.color = _daylight.color.lerp(_daylight_target, 0.05)
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_weather or _plot.is_empty():
		return
	_next_weather = now + 1.0
	var server := _server_now()
	var sun: Dictionary = _plot.get("sun", {})
	var day := true
	var sun_change := 0.0
	if not sun.is_empty():
		var day_ms := float(sun["dayMs"])
		var into := fposmod(server - float(sun["epoch"]), day_ms)
		day = into < float(sun["daylightMs"])
		sun_change = (float(sun["daylightMs"]) if day else day_ms) - into
	var sandstorm := false
	if _sandy():
		_weather.visible = true
		var light := "Dzień (zmierzch za %s)" % _clock_text(sun_change) if day else "Noc: panele nie dają prądu (świt za %s)" % _clock_text(sun_change)
		_weather.text = light
		_weather.add_theme_color_override("font_color", UI.MUTED)
		for storm: Dictionary in _plot.get("sandstorms", []):
			var start := float(storm["start"])
			var end := float(storm["end"])
			if end <= server:
				continue
			if start <= server:
				sandstorm = true
				_weather.text = "Burza piaskowa! Panele bez osłony dają ćwierć prądu, wydmy wracają (jeszcze %s) · %s" % [_clock_text(end - server), light]
				_weather.add_theme_color_override("font_color", UI.ERROR)
			else:
				_weather.text = "%s · burza piaskowa za %s" % [light, _clock_text(start - server)]
			break
	_daylight_target = Color(1.0, 0.86, 0.62) if sandstorm else (Color.WHITE if day else Color(0.62, 0.66, 0.85))
	if _biome() in POLAR:
		_update_polar_weather(server, day, sun_change)
		return
	if _sandy() or not int(_plot.get("biome", -1)) in [COAST, LAKESHORE]:
		return
	for storm: Dictionary in _plot.get("storms", []):
		var start := float(storm["start"])
		var end := float(storm["end"])
		if end <= server:
			continue
		_weather.visible = true
		if start <= server:
			_weather.text = "Sztorm! Łodzie stoją, wędką tylko z falochronu (jeszcze %s)" % _clock_text(end - server)
			_weather.add_theme_color_override("font_color", UI.ERROR)
		else:
			_weather.text = "Spokojne morze · sztorm za %s" % _clock_text(start - server)
			_weather.add_theme_color_override("font_color", UI.MUTED)
		return
	_weather.visible = false


## On the glacier the blizzards, and on the glacier and the tundra the aurora on some nights: the line over the plot,
## the light and the snow blowing across the screen.
func _update_polar_weather(server: float, day: bool, sun_change: float) -> void:
	_weather.visible = true
	_weather.add_theme_color_override("font_color", UI.MUTED)
	var parts: Array[String] = []
	var blizzard := false
	if _biome() == GLACIER:
		for storm: Dictionary in _plot.get("blizzards", []):
			var start := float(storm["start"])
			var end := float(storm["end"])
			if end <= server:
				continue
			if start <= server:
				blizzard = true
				parts.append("Zamieć! Turbiny stoją, lód odrasta, lawiny sypią zaspy (jeszcze %s)" % _clock_text(end - server))
				_weather.add_theme_color_override("font_color", UI.ERROR)
			else:
				parts.append("zamieć za %s" % _clock_text(start - server))
			break
	var aurora := _aurora_now()
	if aurora:
		parts.append("Zorza polarna! Turyści płacą potrójnie (świt za %s)" % _clock_text(sun_change))
		if not blizzard:
			_weather.add_theme_color_override("font_color", Color(0.55, 1.0, 0.7))
	elif day:
		parts.append("Dzień (zmierzch za %s)" % _clock_text(sun_change))
	else:
		var next := _next_aurora(server)
		parts.append("Noc bez zorzy" + (" · następna zorza za %s" % _clock_text(next - server) if next > 0.0 else ""))
	_weather.text = " · ".join(parts)
	_snow.emitting = blizzard
	if blizzard:
		_daylight_target = Color(0.82, 0.86, 0.94)
	elif aurora:
		_daylight_target = Color(0.55, 0.8, 0.72)
	if _was_blizzard and not blizzard:
		# The ice dug away has frozen again and the avalanches left snow about: the plot's tiles are fetched again.
		_refresh_tiles()
	_was_blizzard = blizzard


func _aurora_now() -> bool:
	var server := _server_now()
	for night: Dictionary in _plot.get("auroras", []):
		if float(night["start"]) <= server and server < float(night["end"]):
			return true
	return false


## When the next aurora begins, or 0 when the forecast does not reach it.
func _next_aurora(server: float) -> float:
	for night: Dictionary in _plot.get("auroras", []):
		if float(night["start"]) > server:
			return float(night["start"])
	return 0.0


## Fetches the plot's tiles again (after a blizzard) and redraws them, with the forecast that came with them.
func _refresh_tiles() -> void:
	var reply := await Net.request("plot.enter", {"x": _at.x, "y": _at.y})
	if reply["type"] == "error":
		return
	var plot: Dictionary = reply["payload"]
	for key: String in ["blizzards", "auroras", "sun"]:
		if plot.has(key):
			_plot[key] = plot[key]
	_tiles = Marshalls.base64_to_raw(plot["tiles"]).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	for y in _size:
		for x in _size:
			var cell := Vector2i(x, y)
			_astar.set_point_solid(cell, _solid(cell))
	if _work.x >= 0 and not WORK.has(_work_kind(_work)):
		_stop_work()
	for chunk: Vector2i in _chunks:
		for y in CHUNK:
			for x in CHUNK:
				_draw_cell(chunk * CHUNK + Vector2i(x, y))
	_build_minimap()
	_show_toast("Zamieć ucichła: lód odrósł, a lawiny zostawiły zaspy. Odkop je łopatą.", UI.MUTED)


## Milliseconds as m:ss, or h:mm:ss from an hour up.
func _clock_text(ms: float) -> String:
	var seconds := ceili(ms / 1000.0)
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]
	return "%d:%02d" % [seconds / 60, seconds % 60]


func _screen(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


func _update_prompt() -> void:
	var text := ""
	var placed := _nearest_placed()
	if _work.x < 0 and placed.x >= 0:
		if not (_using == placed and _using_window_open()):
			text = "[E] %s" % _placed[placed]["name"]
	elif _work.x < 0 and _near_station() and not _station_window.visible:
		text = "[E] Stacja kolejowa"
	elif _work.x < 0:
		var cell := _nearest_work()
		var mine := _nearest_mine()
		if cell.x < 0 and mine >= 0:
			text = "[E] Wydobywaj: kopalnia (%d/%d)" % [_mine_left_units(mine), _mine_capacity(mine)]
		elif cell.x >= 0:
			if _fields.has(cell):
				text = "[E] Zbierz: %s" % _crops[_fields[cell]["crop"]]["name"].to_lower()
			else:
				var work: Dictionary = WORK[_work_kind(cell)]
				text = "[E] %s: %s" % [work["verb"], work["name"].to_lower()]
	_prompt.visible = text != ""
	if _prompt.visible:
		_prompt.text = text
		_prompt.reset_size()
		_prompt.position = _screen(_player.position) - Vector2(_prompt.size.x / 2, 100 * _zoom + 30)


# --- HUD ---------------------------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Control.new()
	# The theme of the root window does not reach through the canvas layer.
	_hud.theme = UI.theme()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	var parts := UI.panel(2)
	var info: PanelContainer = parts[0]
	info.position = Vector2(12, 12)
	_hud.add_child(info)
	var box: VBoxContainer = parts[1]
	_title = UI.label("Działka", UI.GOLD)
	_title.add_theme_font_override("font", UI.bold())
	_title.add_theme_font_size_override("font_size", 18)
	box.add_child(_title)
	_subtitle = UI.label("", UI.MUTED)
	box.add_child(_subtitle)
	_weather = UI.label("", UI.MUTED)
	_weather.visible = false
	box.add_child(_weather)
	# The name and level open the character: clothes and a new look.
	var me := VBoxContainer.new()
	me.add_theme_constant_override("separation", 2)
	me.mouse_filter = Control.MOUSE_FILTER_STOP
	me.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	me.tooltip_text = "Postać: ubrania i wygląd  [C]"
	me.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_character_window.toggle()
			me.accept_event())
	box.add_child(me)
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 8)
	var portrait := CharacterPreview.new()
	portrait.options = Game.appearance_options
	portrait.appearance = Game.look()
	portrait.region = Rect2(0.3, 0.06, 0.4, 0.12)
	portrait.display_scale = 0.45
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_row.add_child(portrait)
	Game.character_changed.connect(_on_character_changed.bind(portrait))
	var name_label := UI.label(Game.character.get("name", ""))
	name_label.add_theme_font_override("font", UI.bold())
	level_row.add_child(name_label)
	_level = UI.label("", UI.GOLD)
	level_row.add_child(_level)
	me.add_child(level_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(200, 8)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	me.add_child(_xp_bar)
	_refresh_character()

	var money_parts := UI.panel(0)
	var money_panel: PanelContainer = money_parts[0]
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	money_row.add_child(UI.icon("coin", 22))
	_money = UI.label("", UI.GOLD)
	_money.add_theme_font_override("font", UI.bold())
	_money.add_theme_font_size_override("font_size", 17)
	money_row.add_child(_money)
	money_parts[1].add_child(money_row)
	_hud.add_child(money_panel)
	money_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	money_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# The tool in hand, bottom left.
	var tool_parts := UI.panel(2)
	var tool_panel: PanelContainer = tool_parts[0]
	var tool_label := UI.label("Narzędzia i plecak", UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	tool_label.add_theme_font_size_override("font_size", 12)
	tool_parts[1].add_child(tool_label)
	_tool_slot = ToolSlot.new()
	_tool_slot.changed.connect(_on_tool_changed)
	_tool_slot.failed.connect(_show_error)
	tool_parts[1].add_child(_tool_slot)
	_hud.add_child(tool_panel)
	tool_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	tool_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.add_child(UI.toolbar_button("inventory", "Ekwipunek  [I]", func() -> void:
		_inventory_window.toggle()
		if _inventory_window.visible:
			_reload_inventory()))
	bar.add_child(UI.toolbar_button("station", "Stacja kolejowa  [T]", _go_to_station))
	_market_button = UI.toolbar_button("market", "Rynek  [M]\nPrzez komputer stojący na działce", _toggle_market)
	_market_button.visible = false
	bar.add_child(_market_button)
	bar.add_child(UI.toolbar_button("company", "Spółka  [K]", func() -> void: _company_window.toggle()))
	bar.add_child(UI.toolbar_button("bank", "Banki  [B]\nKonta, wpłaty, wypłaty i przelewy", func() -> void: _bank_window.toggle()))
	_city_button = UI.toolbar_button("city", "Miasto\nPotrzeby, rozwój, śmieci, usługi i ratusz", _toggle_city)
	_city_button.visible = false
	bar.add_child(_city_button)
	_plant_button = UI.toolbar_button("plant", "", func() -> void: _set_planting(not _planting))
	# The number of saplings, in the button's corner.
	_plant_count = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_plant_count.add_theme_font_override("font", UI.bold())
	_plant_count.add_theme_font_size_override("font_size", 11)
	_plant_count.add_theme_constant_override("outline_size", 4)
	_plant_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_plant_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plant_button.add_child(_plant_count)
	_plant_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 1)
	_plant_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_plant_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.add_child(_plant_button)
	_update_plant_button()
	_mine_button = UI.toolbar_button("mine_upgrade", "Rozbuduj kopalnię  [U]\nRozbudowana kopalnia daje więcej jednostek, szybciej i szybciej się odnawia.", _toggle_mine_window)
	_mine_button.visible = false
	bar.add_child(_mine_button)
	bar.add_child(UI.toolbar_button("stats", "Statystyki  [L]", func() -> void: _stats_window.toggle()))
	bar.add_child(UI.toolbar_button("world_map", "Mapa świata  [N]", Game.open_world_map))
	bar.add_child(UI.toolbar_button("achievements", "Osiągnięcia  [O]", func() -> void: _achievements_window.toggle()))
	bar.add_child(UI.toolbar_button("garage", "Garaż  [G]", Game.open_garage))
	_hud.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# The whole plot in small, bottom right.
	var map_parts := UI.panel(0)
	var map_panel: PanelContainer = map_parts[0]
	_minimap = TextureRect.new()
	_minimap.custom_minimum_size = Vector2(150, 150)
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	_minimap.tooltip_text = "Mapa działki: kliknij, aby tam pójść"
	_minimap.gui_input.connect(_on_minimap_input)
	map_parts[1].add_child(_minimap)
	_minimap_dot = ColorRect.new()
	(_minimap_dot as ColorRect).color = UI.GOLD
	_minimap_dot.size = Vector2(5, 5)
	_minimap_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.add_child(_minimap_dot)
	_others.minimap = _minimap
	_hud.add_child(map_panel)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_hint = _outlined(UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.size = Vector2(1280, 20)
	_hint.position = Vector2(0, 640)
	_hud.add_child(_hint)

	_prompt = _outlined(UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_prompt.visible = false
	_hud.add_child(_prompt)

	_field_label = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_field_label.add_theme_font_size_override("font_size", 14)
	_field_label.visible = false
	_hud.add_child(_field_label)

	_crop_menu = PopupMenu.new()
	_crop_menu.add_theme_constant_override("icon_max_width", 26)
	_crop_menu.id_pressed.connect(_on_crop_chosen)
	_crop_menu.popup_hide.connect(func() -> void:
		await get_tree().process_frame
		if not _crop_menu.visible:
			_menu_cell = Vector2i(-1, -1))
	_hud.add_child(_crop_menu)

	_object_menu = PopupMenu.new()
	_object_menu.id_pressed.connect(_on_object_chosen)
	_hud.add_child(_object_menu)

	_animal_menu = PopupMenu.new()
	_animal_menu.add_theme_constant_override("icon_max_width", 26)
	_animal_menu.id_pressed.connect(_on_animal_chosen)
	_animal_menu.popup_hide.connect(func() -> void:
		await get_tree().process_frame
		if not _animal_menu.visible:
			_menu_animal = Vector2i(-1, -1))
	_hud.add_child(_animal_menu)

	_work_bar = ProgressBar.new()
	_work_bar.show_percentage = false
	_work_bar.step = 0.0
	_work_bar.custom_minimum_size = Vector2(70, 9)
	_work_bar.size = Vector2(70, 9)
	_work_bar.visible = false
	_work_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_work_bar)

	_toast = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_toast.size = Vector2(900, 30)
	_toast.position = Vector2(190, 600)
	_toast.modulate.a = 0.0
	_hud.add_child(_toast)

	_loading = UI.title("Wchodzę na działkę...", 22)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.add_child(_loading)


func _outlined(label: Label) -> Label:
	label.add_theme_font_override("font", UI.bold())
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh_character() -> void:
	var c := Game.character
	var xp: int = c.get("xp", 0)
	var level_xp: int = c.get("levelXp", 0)
	var next_xp: Variant = c.get("nextLevelXp")
	_level.text = "Poziom %d" % c.get("level", 1)
	_xp_bar.max_value = (next_xp - level_xp) if next_xp != null else 1.0
	_xp_bar.value = xp - level_xp if next_xp != null else 1.0
	_xp_bar.tooltip_text = "%d / %d XP" % [xp, next_xp] if next_xp != null else "%d XP" % xp


func _on_tool_changed() -> void:
	var names := Game.tools().map(func(t: Dictionary) -> String: return t["name"])
	_show_toast("W ręku: %s" % ", ".join(names) if not names.is_empty() else "Narzędzia schowane do ekwipunku.")
	_update_hint()
	if _inventory_window.visible or _station_window.visible:
		_reload_inventory()


func _update_hint() -> void:
	var lines := {
		"tool_axe": "Kliknij drzewo, aby je ściąć siekierą.",
		"tool_chainsaw": "Kliknij drzewo, aby je ściąć piłą spalinową (o 70% szybciej niż siekierą).",
		"tool_steel_saw": "Kliknij drzewo: piła stalowa ścina je w 1 s i daje o 1 drewno więcej.",
		"tool_harvester_saw": "Kliknij drzewo: piła harwesterowa ścina je razem z 2 sąsiednimi.",
		"tool_meteorite_saw": "Kliknij drzewo: piła meteorytowa ścina je w 0,5 s razem z 4 sąsiednimi.",
		"tool_pickaxe": "Kliknij bryłę lodu, skałę albo meteoryt, aby je rozbić kilofem. Szczelinę przekryjesz mostem z 3 belek." if _biome() == GLACIER \
			else ("Kliknij kopalnię, aby wydobywać rudy, albo skałę, aby ją rozbić kilofem." if not _mines.is_empty() else "Kliknij skałę, aby ją rozbić kilofem."),
		"tool_bronze_pickaxe": "Kliknij kopalnię albo skałę: kilof z brązu kopie o 25% szybciej niż żelazny.",
		"tool_steel_pickaxe": "Kliknij kopalnię albo skałę: kilof stalowy kopie o 50% szybciej niż żelazny.",
		"tool_meteorite_pickaxe": "Kliknij kopalnię, skałę albo lód: kilof z meteorytu kopie dwa razy szybciej niż żelazny.",
		"tool_shovel": "Kliknij zaspę, aby ją odkopać łopatą." if _biome() == GLACIER else "Kliknij wydmę, aby ją przekopać łopatą.",
		"tool_hoe": "Kliknij wolną ziemię, aby ją zaorać motyką, a pole, aby zasiać." if _fertile else "Motyką orze się tylko żyzne gleby.",
		"tool_shears": "Kliknij owcę, aby ją ostrzyc nożycami, albo inne zwierzę, aby je nakarmić." if _pasture else "Na tej działce nie da się trzymać zwierząt.",
	}
	if _placing in MACHINERY:
		_hint.text = "Stawianie: kliknij wolne pole, aby postawić %s %s %s. [R] obraca, Esc kończy." % [
			_item_name(_placing).to_lower(), DIRECTION_ARROWS[_place_rotation], DIRECTIONS[_place_rotation]]
		return
	if _placing != "":
		_hint.text = "Stawianie: kliknij wolne pole, aby postawić %s. Esc anuluje." % _item_name(_placing).to_lower()
		return
	if _planting:
		_hint.text = "Sadzenie: kliknij wolne pole, aby posadzić: %s (masz %d). [P] lub Esc kończy." % [_item_name(_planting_sapling).to_lower(), _saplings]
		return
	if _releasing != "":
		_hint.text = "Wypuszczanie: kliknij wolne pole, aby wypuścić: %s (masz %d). Esc kończy." % [_item_name(_releasing).to_lower(), _count(_releasing)]
		return
	var held := Game.tools().map(func(t: Dictionary) -> String: return t["id"])
	# A saw does an axe's work, faster, so only the best saw's line stays.
	var saws := ["tool_meteorite_saw", "tool_harvester_saw", "tool_steel_saw", "tool_chainsaw", "tool_axe"]
	var best := saws.filter(func(id: String) -> bool: return id in held)
	for id: String in saws:
		if not best.is_empty() and id != best[0]:
			held.erase(id)
	if held.is_empty() and _fertile:
		lines[""] = "Kliknij pole, aby zasiać lub zebrać plony. Do orania weź motykę [Q]."
	if held.is_empty() and _pasture and not _animals.is_empty():
		lines[""] = "Kliknij zwierzę, aby je nakarmić albo zebrać, co daje."
	var parts := held.map(func(id: String) -> String: return lines.get(id, "")).filter(func(line: String) -> bool: return line != "")
	_hint.text = " ".join(parts) if not parts.is_empty() else lines.get("", "Bez narzędzia nic tu nie zbierzesz. Narzędzia dostajesz za zakup działki w lesie, na pustyni, w górach, na żyznych glebach lub na stepie.")
	_hint.text += "  ·  Stacja kolejowa [T] wysyła towary do innych fabryk."


func _set_balance(cents: int) -> void:
	_balance = cents
	_money.text = UI.money(cents)
	_market_window.set_player(_items, _balance)
	_station_window.set_player(_items, cents)


func _reload_balance() -> void:
	var wallet := await Net.request("wallet.get")
	if wallet["type"] == "wallet":
		_set_balance(int(wallet["payload"]["balanceCents"]))


# --- Minimap ------------------------------------------------------------------------------------------

func _build_minimap() -> void:
	_minimap_image = Image.create(_size, _size, false, Image.FORMAT_RGBA8)
	var floor_tint := Color(0.16, 0.16, 0.15)
	_minimap_image.fill(floor_tint)
	for y in _size:
		for x in _size:
			var kind := _tiles[y * _size + x]
			if kind != NONE and MINIMAP_COLORS.has(kind):
				_minimap_image.set_pixel(x, y, MINIMAP_COLORS[kind])
	for cell: Vector2i in _fields:
		_minimap_image.set_pixelv(cell, FIELD_COLOR)
	for cell: Vector2i in _trees:
		_minimap_image.set_pixelv(cell, MINIMAP_COLORS[TREE])
	# Mines stand out a little larger than they are, so they are easy to find.
	for mine: Dictionary in _mines.values():
		_minimap_image.fill_rect(Rect2i(int(mine["x"]) - 1, int(mine["y"]) - 1, int(mine["width"]) + 2, int(mine["height"]) + 2), MINIMAP_COLORS[MINE])
	_minimap.texture = ImageTexture.create_from_image(_minimap_image)
	# The plot is wider than tall on screen; keep the minimap's proportions the same.
	_minimap.custom_minimum_size = Vector2(170, 170 * TILE.y / TILE.x)


func _set_minimap(cell: Vector2i, kind: int) -> void:
	var colour: Color = MINIMAP_COLORS[kind] if kind != NONE else Color(0.16, 0.16, 0.15)
	if _trees.has(cell):
		colour = MINIMAP_COLORS[TREE]
	_minimap_image.set_pixelv(cell, FIELD_COLOR if _fields.has(cell) else colour)
	(_minimap.texture as ImageTexture).update(_minimap_image)


func _update_minimap_dot() -> void:
	var scale := _minimap.size / float(_size)
	_minimap_dot.position = _player.floor_pos * scale - _minimap_dot.size / 2


func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := Vector2i((event.position / _minimap.size * _size).floor())
		_stop_work()
		_walk_to(cell, Callable(), _solid(cell))


# --- Windows -----------------------------------------------------------------------------------------

func _build_windows() -> void:
	_inventory_window = GameWindow.new("Ekwipunek", 0)
	_inventory_window.position = Vector2(12, 150)
	_slots = InventoryGrid.new()
	_slots.hint = func(item: String) -> String:
		if item in SAPLINGS:
			return "Kliknij, aby sadzić na działce"
		if item == INSECTICIDE:
			return "Kliknij, aby opryskać drzewa na działce przed kornikiem"
		if ANIMAL_SPRITES.has(item):
			return "Kliknij, aby wypuścić na działce"
		if PLACED_SPRITES.has(item) or item in BELTS:
			return "Kliknij, aby postawić na działce"
		if item in ToolSlot.BACKPACKS:
			return "Kliknij, aby założyć"
		return "Kliknij, aby wziąć do ręki" if item in ToolSlot.TOOLS else ""
	_slots.clicked.connect(func(item: String) -> void:
		if item in ToolSlot.TOOLS or item in ToolSlot.BACKPACKS:
			_tool_slot.equip(item)
		elif item in SAPLINGS:
			_inventory_window.hide_window()
			_planting_sapling = item
			_set_saplings(int(_sapling_counts.get(item, 0)))
			_set_planting(true)
		elif item == INSECTICIDE:
			_spray_forest()
		elif ANIMAL_SPRITES.has(item):
			_start_releasing(item)
		elif PLACED_SPRITES.has(item) or item in BELTS:
			_start_placing(item))
	_slots.changed.connect(func(items: Array) -> void:
		_items = items
		_count_saplings(items))
	_slots.failed.connect(_show_error)
	_inventory_window.content.add_child(_slots)
	_inventory_window.content.add_child(UI.label("Przeciągnij przedmiot na inny kafelek, aby zmienić kolejność.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_station_window = StationWindow.new()
	_station_window.position = Vector2(1280 - 470 - 12, 64)
	_station_window.inventory_changed.connect(_reload_inventory)
	_station_window.balance_changed.connect(_reload_balance)
	_station_window.failed.connect(_show_error)
	_station_window.toast.connect(func(text: String) -> void: _show_toast(text, UI.GOLD))
	_crafting_window = CraftingWindow.new()
	_crafting_window.can_pick_up = true
	_crafting_window.position = Vector2(1280 - 400 - 12, 64)
	_crafting_window.finished.connect(_on_crafted)
	_crafting_window.inventory_changed.connect(_reload_inventory)
	_crafting_window.failed.connect(_show_error)
	_crafting_window.pick_up_requested.connect(_pick_up_placed)
	_research_window = ResearchWindow.new()
	_research_window.can_pick_up = true
	_research_window.inventory_changed.connect(_reload_inventory)
	_research_window.balance_changed.connect(_reload_balance)
	_research_window.failed.connect(_show_error)
	_research_window.researched.connect(_on_researched)
	_research_window.pick_up_requested.connect(_pick_up_placed)
	_furnace_window = FurnaceWindow.new()
	_furnace_window.can_pick_up = true
	_furnace_window.position = Vector2(1280 - 400 - 12, 64)
	_furnace_window.inventory_changed.connect(_on_furnace_changed)
	_furnace_window.failed.connect(_show_error)
	_furnace_window.pick_up_requested.connect(_pick_up_placed)
	_storage_window = StorageWindow.new()
	_storage_window.position = Vector2(1280 - 420 - 12, 64)
	_storage_window.inventory_changed.connect(func() -> void:
		_reload_inventory()
		_poll_logistics())
	_storage_window.failed.connect(_show_error)
	_storage_window.pick_up_requested.connect(_pick_up_placed)
	_splitter_window = SplitterWindow.new()
	_splitter_window.position = Vector2(1280 - 400 - 12, 64)
	_splitter_window.applied.connect(_logistics.apply)
	_splitter_window.failed.connect(_show_error)
	_filter_window = FilterWindow.new()
	_filter_window.position = Vector2(1280 - 400 - 12, 64)
	_filter_window.applied.connect(_logistics.apply)
	_filter_window.failed.connect(_show_error)
	_mine_window = GameWindow.new("Kopalnia", 400)
	_mine_window.position = Vector2(1280 - 400 - 12, 64)
	_mine_box = VBoxContainer.new()
	_mine_box.add_theme_constant_override("separation", 6)
	_mine_window.content.add_child(_mine_box)
	_machine_window = MachineWindow.new()
	_machine_window.position = Vector2(1280 - 420 - 12, 64)
	_machine_window.inventory_changed.connect(_on_furnace_changed)
	_machine_window.failed.connect(_show_error)
	_machine_window.pick_up_requested.connect(_pick_up_placed)
	_forester_window = ForesterWindow.new()
	_forester_window.position = Vector2(1280 - 420 - 12, 64)
	_forester_window.updated.connect(_apply_forestry)
	_forester_window.inventory_changed.connect(_on_furnace_changed)
	_forester_window.failed.connect(_show_error)
	_forester_window.pick_up_requested.connect(_pick_up_placed)
	_farmstead_window = FarmsteadWindow.new()
	_farmstead_window.position = Vector2(1280 - 420 - 12, 64)
	_farmstead_window.updated.connect(_apply_farmsteads)
	_farmstead_window.inventory_changed.connect(_on_furnace_changed)
	_farmstead_window.failed.connect(_show_error)
	_farmstead_window.pick_up_requested.connect(_pick_up_placed)
	_canteen_window = CanteenWindow.new()
	_canteen_window.position = Vector2(1280 - 400 - 12, 64)
	_canteen_window.inventory_changed.connect(func() -> void: _reload_inventory())
	_canteen_window.failed.connect(_show_error)
	_canteen_window.pick_up_requested.connect(_pick_up_placed)
	_generator_window = GeneratorWindow.new()
	_generator_window.position = Vector2(1280 - 400 - 12, 64)
	_generator_window.inventory_changed.connect(func(_taken: Array, _xp: Variant) -> void:
		_reload_inventory()
		_poll_logistics())
	_generator_window.failed.connect(_show_error)
	_generator_window.pick_up_requested.connect(_pick_up_placed)
	_drill_window = DrillWindow.new()
	_drill_window.position = Vector2(1280 - 420 - 12, 64)
	_drill_window.inventory_changed.connect(_on_furnace_changed)
	_drill_window.failed.connect(_show_error)
	_drill_window.pick_up_requested.connect(_pick_up_placed)
	_well_window = WellWindow.new()
	_well_window.position = Vector2(1280 - 420 - 12, 64)
	_well_window.inventory_changed.connect(_on_furnace_changed)
	_well_window.failed.connect(_show_error)
	_well_window.pick_up_requested.connect(_pick_up_placed)
	_shop_window = ShopWindow.new()
	_shop_window.position = Vector2(1280 - 480 - 12, 64)
	_shop_window.inventory_changed.connect(_reload_inventory)
	_shop_window.balance_changed.connect(_reload_balance)
	_shop_window.failed.connect(_show_error)
	_shop_window.pick_up_requested.connect(_pick_up_placed)
	_export_window = ExportWindow.new()
	_export_window.position = Vector2(1280 - 500 - 12, 64)
	_export_window.inventory_changed.connect(_reload_inventory)
	_export_window.balance_changed.connect(_reload_balance)
	_export_window.failed.connect(_show_error)
	_export_window.pick_up_requested.connect(_pick_up_placed)
	_export_post_window = ExportPostWindow.new()
	_export_post_window.position = Vector2(1280 - 440 - 12, 64)
	_export_post_window.balance_changed.connect(_reload_balance)
	_export_post_window.failed.connect(_show_error)
	_export_post_window.pick_up_requested.connect(_pick_up_placed)
	_hive_window = HiveWindow.new()
	_hive_window.position = Vector2(1280 - 400 - 12, 64)
	_hive_window.inventory_changed.connect(_reload_inventory)
	_hive_window.failed.connect(_show_error)
	_hive_window.pick_up_requested.connect(_pick_up_placed)
	_city_window = CityWindow.new()
	_city_window.position = Vector2(1280 - 520 - 12, 64)
	_city_window.inventory_changed.connect(_reload_inventory)
	_city_window.balance_changed.connect(_reload_balance)
	_city_window.failed.connect(_show_error)
	_city_window.toast.connect(func(text: String) -> void: _show_toast(text, UI.GOLD))
	_company_window = CompanyWindow.new()
	_company_window.position = Vector2(1280 - 520 - 12, 64)
	_company_window.inventory_changed.connect(_reload_inventory)
	_company_window.balance_changed.connect(_reload_balance)
	_company_window.failed.connect(_show_error)
	_stats_window = StatsWindow.new()
	_stats_window.position = Vector2(1280 - 640 - 12, 64)
	_stats_window.failed.connect(_show_error)
	var layer := _hud
	layer.add_child(_stats_window)
	layer.add_child(_inventory_window)
	layer.add_child(_company_window)
	layer.add_child(_storage_window)
	layer.add_child(_splitter_window)
	layer.add_child(_filter_window)
	layer.add_child(_station_window)
	layer.add_child(_crafting_window)
	layer.add_child(_research_window)
	layer.add_child(_furnace_window)
	layer.add_child(_machine_window)
	layer.add_child(_forester_window)
	layer.add_child(_farmstead_window)
	layer.add_child(_canteen_window)
	_market_window = MarketWindow.new()
	_market_window.traded.connect(_on_traded)
	_market_window.failed.connect(_show_error)
	_market_window.pick_up_requested.connect(_pick_up_placed)
	layer.add_child(_market_window)
	layer.add_child(_mine_window)
	layer.add_child(_generator_window)
	layer.add_child(_drill_window)
	layer.add_child(_well_window)
	layer.add_child(_shop_window)
	layer.add_child(_hive_window)
	layer.add_child(_export_window)
	layer.add_child(_export_post_window)
	_bank_window = BankWindow.new()
	_bank_window.position = Vector2(1280 - 520 - 12, 64)
	_bank_window.balance_changed.connect(_reload_balance)
	_bank_window.failed.connect(_show_error)
	layer.add_child(_bank_window)
	layer.add_child(_city_window)
	_achievements_window = AchievementsWindow.new()
	_achievements_window.failed.connect(_show_error)
	layer.add_child(_achievements_window)
	_character_window = CharacterWindow.new()
	_character_window.position = Vector2(280, 60)
	_character_window.failed.connect(_show_error)
	_character_window.balance_changed.connect(_reload_balance)
	layer.add_child(_character_window)


func _reload_inventory() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		return
	_items = reply["payload"]["items"]
	_count_saplings(_items)
	_slots.show_items(reply["payload"])
	_crafting_window.set_items(_items)
	_research_window.set_items(_items)
	_furnace_window.set_items(_items)
	_storage_window.set_items(_items)
	_splitter_window.set_items(_items)
	_filter_window.set_items(_items)
	_machine_window.set_items(_items)
	_market_window.set_player(_items, _balance)
	_generator_window.set_items(_items)
	_station_window.set_player(_items, _balance)
	if _mine_window.visible:
		_render_mine_window()


func _refresh_station() -> void:
	_station_window.port = _placed.values().any(func(object: Dictionary) -> bool: return object["kind"] == PORT)
	_station_window.sled = _biome() in POLAR and _placed.values().any(func(object: Dictionary) -> bool:
		return object["kind"] in ["furniture_dog_kennel", "furniture_snowmobile_garage"])
	_station_window.horse = not _biome() in POLAR and _placed.values().any(func(object: Dictionary) -> bool: return object["kind"] == STABLE)
	await _station_window.refresh()
	_show_trains()


## Trains on the track, from what the station said last; asked again every few seconds, more
## often while a train is at the platform.
func _show_trains() -> void:
	var station := _station_window.state()
	if station.is_empty():
		return
	_clock_offset = float(station["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_trains.show_station(station, _at)


func _poll_station() -> void:
	if Time.get_ticks_msec() < _next_station_poll:
		return
	_next_station_poll = Time.get_ticks_msec() + (STATION_POLL / 2.0 if _trains.busy() else STATION_POLL)
	_refresh_station()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


# --- Server ---------------------------------------------------------------------------------------------

func _load() -> void:
	_at = Game.plot
	var info := await Net.request("world.info")
	var wallet := await Net.request("wallet.get")
	var plot := await Net.request("plot.enter", {"x": _at.x, "y": _at.y})
	var prices := await Net.request("market.prices")
	for reply: Dictionary in [info, wallet, plot, prices]:
		if reply["type"] == "error":
			_loading.text = Game.error_text(reply)
			await get_tree().create_timer(2.0).timeout
			Game.open_world_map()
			return
	_world_width = info["payload"]["width"]
	for biome: Dictionary in info["payload"]["biomes"]:
		_biome_names[int(biome["id"])] = biome["name"]
	for owned: Dictionary in info["payload"]["plots"]:
		_my_plots.append(Vector2i(owned["x"], owned["y"]))
	_station_window.plot = _at
	_station_window.world_width = _world_width
	_station_window.my_plots = _my_plots
	_trains.world_width = _world_width
	_set_balance(int(wallet["payload"]["balanceCents"]))
	_market_window.set_prices(prices["payload"]["items"])
	_apply_plot(plot["payload"])
	_show_forest_news(plot["payload"])
	_update_market_button()
	_title.text = "Działka %d × %d" % [_at.x, _at.y]
	_subtitle.text = "%s  ·  5 × 5 km" % _biome_names.get(int(plot["payload"]["biome"]), "?")
	var city: Variant = plot["payload"].get("city")
	_city_button.visible = city != null
	if city != null:
		_subtitle.text = "%s %s  ·  5 × 5 km" % [city["levelName"], city["name"]]
	_update_hint()
	_loading.queue_free()
	_reload_inventory()
	# Orders made while the player was away land in the inventory now.
	_crafting_window.refresh()
	# Research that ended while the player was away is announced now.
	_research_window.refresh()
	_poll_logistics()


# --- Effects ---------------------------------------------------------------------------------------------

func _float_text(text: String, color: Color, at: Vector2, delay := 0.0, item := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item != "":
		var icon := UI.item_icon(item, 26)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var l := _outlined(UI.label(text, color))
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	row.modulate.a = 0.0
	_hud.add_child(row)
	row.reset_size()
	# Lines shown one after another stack downwards, so they never cover each other.
	var start := _screen(at) + Vector2(-row.size.x / 2, -120 * _zoom + delay * 110)
	row.position = start
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(row, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(row, "position:y", start.y - 50, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "modulate:a", 0.0, 0.4)
	tween.tween_callback(row.queue_free)


func _toggle_city() -> void:
	if _city_window.visible:
		_city_window.hide_window()
	else:
		_city_window.open_at(_at)


func _show_toast(text: String, color := UI.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


## New clothes or a new look: the portrait and the character on the plot follow.
func _on_character_changed(portrait: CharacterPreview) -> void:
	portrait.appearance = Game.look()
	_player.set_look(Game.look(), Game.appearance_options)


func _show_error(reply: Dictionary) -> void:
	_show_toast(Game.error_text(reply), UI.ERROR)
