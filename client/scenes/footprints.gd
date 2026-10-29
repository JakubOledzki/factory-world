class_name Footprints
## The tiles an object covers on a plot, as the server's Footprints: a square of size × size tiles. Belts, inserters, chests and
## poles stand on one tile. Machines grow with their level: the first level 2 × 2 (two inserters fit along a side), the next 3 × 3
## and the best 4 × 4. An odd square is centred on the object's tile, an even one has that tile as the top left of its middle.

## Machines drawn for one tile and grown since: the game draws their sprites bigger.
const GROWN := {
	"furniture_furnace": 2, "furniture_mill": 2, "furniture_oil_press": 2, "furniture_pickling_barrel": 2, "furniture_bakery": 2,
	"furniture_kitchen": 2, "furniture_sawmill": 2, "furniture_quarry": 2, "furniture_crusher": 2, "furniture_stonemason": 2,
	"furniture_smokehouse": 2, "furniture_cannery": 2, "furniture_distillery": 2, "furniture_glassworks": 2, "furniture_cement_kiln": 2,
	"furniture_concrete_mixer": 2, "furniture_ice_melter": 2, "furniture_cold_store": 2, "furniture_paper_mill": 2,
	"furniture_carpentry": 2, "furniture_charcoal_kiln": 2, "furniture_tar_kiln": 2, "furniture_dairy": 2,
	"furniture_slaughterhouse": 2, "furniture_potato_distillery": 2, "furniture_machine_shop": 2, "furniture_multistorey_factory": 2,
	"furniture_brick_furnace": 3, "furniture_electric_sawmill": 3, "furniture_foundry": 3, "furniture_refinery": 3,
	"furniture_cracker": 3, "furniture_chemical_plant": 3, "furniture_arc_furnace": 3,
	"furniture_blast_furnace": 4, "furniture_industrial_sawmill": 4,
}
## Buildings drawn at their size from the start.
const BIG := {
	"furniture_forester_hut": 3, "furniture_forester_lodge": 3, "furniture_forestry_station": 3, "power_solar_tower": 3,
	"power_large_wind_turbine": 3, "furniture_ice_hotel": 3, "furniture_assembly_hall": 3, "furniture_robotic_hall": 3,
	"furniture_oxygen_converter": 3, "furniture_rolling_mill": 3, "furniture_continuous_caster": 3, "storage_automated_warehouse": 3,
	"power_fusion_plant": 3, "power_coal_plant": 3, "power_nuclear_plant": 4, "power_energy_store": 2, "furniture_canteen": 3, "furniture_biogas_plant": 3, "furniture_farmstead": 3, "furniture_manor_farm": 3,
	"furniture_buy_market": 3, "furniture_bank_branch": 3,
	"furniture_assembler": 2, "furniture_fast_assembler": 3, "furniture_express_assembler": 4,
	"furniture_roller_mill": 3, "furniture_flour_works": 4, "furniture_mechanized_quarry": 3, "furniture_open_pit_mine": 4,
	"furniture_cone_crusher": 3, "furniture_ore_processing_plant": 4,
	"furniture_spinning_mill": 2, "furniture_loom": 2, "furniture_sugar_factory": 2, "furniture_jeweler": 2, "furniture_electrolyzer": 2,
	"furniture_tree_nursery": 2, "furniture_auto_barn": 2, "power_fuel_cell": 2,
	"furniture_coke_oven": 3, "power_biomass_plant": 3, "power_chp_plant": 3, "power_geothermal_plant": 3, "furniture_mechanized_farm": 4,
	"furniture_steel_combine": 5, "furniture_megafactory": 5, "furniture_bank": 5,
	"furniture_rail_port": 9,
}


## How many tiles wide (and deep) an object of `kind` is.
static func size(kind: String) -> int:
	return GROWN.get(kind, BIG.get(kind, 1))


## How far its square reaches from its tile up and to the left.
static func low(kind: String) -> int:
	return (size(kind) - 1) / 2


## How far its square reaches from its tile down and to the right.
static func high(kind: String) -> int:
	return size(kind) / 2


## Every tile an object of `kind` standing on `cell` covers.
static func tiles(kind: String, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dy in range(-low(kind), high(kind) + 1):
		for dx in range(-low(kind), high(kind) + 1):
			cells.append(cell + Vector2i(dx, dy))
	return cells


## Where the middle of the square is from the middle of the object's own tile, in tiles: half a tile right and down for an even one.
static func shift(kind: String) -> Vector2:
	return Vector2.ONE * 0.5 * (high(kind) - low(kind))


## How much of its square's width a grown machine fills, and how far above the square's front edge it stands,
## in tiles: the slab under it shows all round, so the player sees which tiles it takes.
const FILL := 0.92
const FOOT := 0.2


## How a grown machine's sprite, drawn for one tile, is fitted to its square: enlarged until what is drawn on it
## (`drawn`, the picture's part that is not clear, on screen) is nearly as wide as the square, and stood in the square's
## middle with its foot just behind the square's front edge. Returns [scale, anchor]: the anchor is the point of the
## enlarged picture that lies on the centre of the object's own tile.
static func fit(kind: String, drawn: Rect2, tile: Vector2) -> Array:
	var n := size(kind)
	var scale := FILL * n * tile.x / drawn.size.x
	var foot := Vector2(drawn.get_center().x, drawn.end.y) * scale
	return [scale, foot - shift(kind) * tile - Vector2(0, (n * 0.5 - FOOT) * tile.y)]
