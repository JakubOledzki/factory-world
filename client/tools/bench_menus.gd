extends Node
## Benchmark: how long the menus take to open on a big plot, from the click to the drawn window.
##   godot --path client res://tools/bench_menus.tscn -- email=... password=... x=... y=...
## Prints one BENCH line per menu (median of a few openings) and "BENCH done" at the end.

var _args := {}


func _ready() -> void:
	OS.low_processor_usage_mode = false
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			_args[pair[0]] = pair[1]
	_run.call_deferred()


func _run() -> void:
	reparent(get_tree().root)
	get_tree().current_scene = null
	while not Net.is_open():
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var reply := await Net.request("auth.login", {"email": _args["email"], "password": _args["password"]})
	if reply["type"] != "auth.ok":
		print("BENCH login failed: ", reply)
		return
	Game.character = (await Net.request("character.get"))["payload"]
	var at := Vector2i(int(_args["x"]), int(_args["y"]))

	var started := Time.get_ticks_usec()
	Game.open_world_map()
	var map := await _scene_where(func(s: Node) -> bool: return s.get("_built") == true and not (s.get("_biomes") as Dictionary).is_empty())
	print("BENCH world map, first time: %.0f ms" % _since(started))
	for i in 2:
		started = Time.get_ticks_usec()
		var old := map.get_instance_id()
		Game.open_world_map()
		await _scene_where(func(s: Node) -> bool: return s.get_instance_id() != old and s.get("_built") == true and not (s.get("_biomes") as Dictionary).is_empty())
		map = get_tree().current_scene
	print("BENCH world map, again: %.0f ms" % _since(started))

	started = Time.get_ticks_usec()
	Game.enter_plot(at)
	var plot := await _scene_where(func(s: Node) -> bool: return s.get("_ready_to_play") == true)
	print("BENCH plot: %.0f ms" % _since(started))
	await get_tree().create_timer(2.0).timeout

	var market: MarketWindow = plot.get("_market_window")
	market.show()
	for tab in [MarketWindow.TRADER, MarketWindow.PLAYERS, MarketWindow.SELL, MarketWindow.MINE]:
		var times: Array[float] = []
		for i in 3:
			market.set("_tab", -1)
			started = Time.get_ticks_usec()
			await market.call("_open_tab", tab)
			times.append(_since(started))
		started = Time.get_ticks_usec()
		market.call("_render")
		print("BENCH market tab %s: %s ms, drawing alone %.0f ms" % [MarketWindow.TABS[tab], _median(times), _since(started)])
		await get_tree().process_frame
	market.set("_item", "iron_ore")
	var board: Array[float] = []
	for i in 3:
		started = Time.get_ticks_usec()
		await market.call("_open_tab", MarketWindow.PLAYERS)
		board.append(_since(started))
	print("BENCH market item: %s ms" % _median(board))
	market.hide()

	var storage: StorageWindow = plot.get("_storage_window")
	var chest := ""
	for o: Dictionary in plot.get("_placed").values():
		if o["kind"] == "storage_wooden_chest":
			chest = o["id"]
			break
	var opened: Array[float] = []
	for i in 3:
		started = Time.get_ticks_usec()
		storage.storage = ""
		storage.open_at(at, chest)
		while (storage.get("_state") as Dictionary).is_empty():
			await get_tree().process_frame
		opened.append(_since(started))
		storage.hide_window()
	print("BENCH chest: %s ms" % _median(opened))
	print("BENCH done")
	get_tree().quit()


func _scene_where(ready: Callable) -> Node:
	while true:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and ready.call(scene):
			return scene
	return null


func _since(started: int) -> float:
	return (Time.get_ticks_usec() - started) / 1000.0


func _median(times: Array[float]) -> String:
	var sorted := times.duplicate()
	sorted.sort()
	return "%.0f" % sorted[sorted.size() / 2]
