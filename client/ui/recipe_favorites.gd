class_name RecipeFavorites
## Recipes the player starred and the ones they used last, kept on this device. The workbench, the
## anvil and every machine show them first, so the few recipes a player makes again and again are at hand.

const FILE := "user://recipes.cfg"
## How many recently used recipes are remembered.
const RECENT := 8

static var _starred: Array = []
static var _recent: Array = []
static var _loaded := false


static func starred(recipe: String) -> bool:
	_load()
	return _starred.has(recipe)


static func toggle(recipe: String) -> void:
	_load()
	if _starred.has(recipe):
		_starred.erase(recipe)
	else:
		_starred.append(recipe)
	_save()


## The recipe was just made or chosen: it goes to the front of the recent ones.
static func used(recipe: String) -> void:
	_load()
	_recent.erase(recipe)
	_recent.push_front(recipe)
	_recent = _recent.slice(0, RECENT)
	_save()


## The starred recipes among `ids`, then the recently used ones, each in its order; the rest left out.
static func first(ids: Array) -> Dictionary:
	_load()
	var starred_here := _starred.filter(func(id: String) -> bool: return ids.has(id))
	var recent_here := _recent.filter(func(id: String) -> bool: return ids.has(id) and not starred_here.has(id))
	return {"starred": starred_here, "recent": recent_here}


## Sorts recipe dictionaries ({id, ...}) with the starred first, then the recent, then the rest as they were.
static func sorted(recipes: Array) -> Array:
	_load()
	var rank := func(recipe: Dictionary) -> int:
		var id: String = recipe["id"]
		if _starred.has(id):
			return _starred.find(id)
		if _recent.has(id):
			return 1000 + _recent.find(id)
		return 1000000
	var indexed := []
	for i in recipes.size():
		indexed.append([rank.call(recipes[i]), i, recipes[i]])
	indexed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return indexed.map(func(entry: Array) -> Dictionary: return entry[2])


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(FILE) == OK:
		_starred = Array(config.get_value("recipes", "starred", []))
		_recent = Array(config.get_value("recipes", "recent", []))


static func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("recipes", "starred", _starred)
	config.set_value("recipes", "recent", _recent)
	config.save(FILE)
