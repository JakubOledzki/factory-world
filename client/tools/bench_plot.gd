extends Node
## Benchmark: logs in, walks onto a plot and measures how long the plot takes to load and how long each frame
## takes there, standing in the middle of its machinery. Run against a server with a big factory plot:
##   godot --headless --path client res://tools/bench_plot.tscn -- email=... password=... x=... y=... [tile_x=20 tile_y=30] [zoom=0.5] [seconds=15]
## off=power,logistics,plot stops those parts working, to see what each costs; hide=_objects,_power hides those layers;
## shot=file.png (run with a screen) saves a picture.
## walk=40 walks the character to and fro that many tiles along the row while measuring, as a player crossing the plot.
## Prints its results; headless, it measures the game's own work per frame (scripts, drawing commands), not the GPU.

var _args := {}
var _phase := "connect"
var _started := 0
var _frames: Array[float] = []
## Time the scripts took each frame (_process), apart from drawing.
var _scripts: Array[float] = []
var _last := 0
var _measure_until := 0
var _plot: Node = null
## The plot scene being left for the second walk onto it.
var _left: Node = null


func _ready() -> void:
	# Headless, the engine sleeps between frames to save power; the benchmark wants the work alone.
	OS.low_processor_usage_mode = false
	OS.low_processor_usage_mode_sleep_usec = 0
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			_args[pair[0]] = pair[1]
	# Lives on the root, not as the current scene, so it stays while scenes change.
	_detach.call_deferred()
	Net.message_received.connect(_on_message)


func _on_message(type: String, _payload: Variant, _id: String) -> void:
	if type == "welcome" and _phase == "connect":
		_phase = "login"
		_login()


func _detach() -> void:
	reparent(get_tree().root)
	get_tree().current_scene = null


func _login() -> void:
	var reply := await Net.request("auth.login", {"email": _args["email"], "password": _args["password"]})
	if reply["type"] != "auth.ok":
		print("BENCH login failed: ", reply)
		get_tree().quit(1)
		return
	var character := await Net.request("character.get")
	Game.character = character["payload"]
	_phase = "loading"
	_started = Time.get_ticks_usec()
	Game.enter_plot(Vector2i(int(_args["x"]), int(_args["y"])))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	match _phase:
		"loading":
			_plot = get_tree().current_scene
			if _plot != null and _plot != _left and _plot.get("_ready_to_play"):
				var loaded := (now - _started) / 1000.0
				print("BENCH plot loaded in %.0f ms" % loaded)
				if not _args.has("loaded"):
					# Once more, as when coming back to the plot: what is kept while the game runs is ready then.
					_args["loaded"] = loaded
					_started = Time.get_ticks_usec()
					Game.enter_plot(Vector2i(int(_args["x"]), int(_args["y"])))
					_left = _plot
					return
				_args["again"] = loaded
				var cell := Vector2(float(_args.get("tile_x", "20")), float(_args.get("tile_y", "30")))
				_plot.call("_place_player", cell + Vector2(0.5, 0.5))
				if _args.has("zoom"):
					_plot.call("_set_zoom", float(_args["zoom"]))
				for layer in String(_args.get("hide", "")).split(",", false):
					(_plot.get(layer) as CanvasItem).visible = false
				for off in String(_args.get("off", "")).split(",", false):
					var node: Node = _plot.get("_" + off) if off != "plot" else _plot
					node.set_process(false)
				_phase = "warmup"
				_measure_until = now + 3_000_000
		"warmup":
			if now >= _measure_until:
				if _args.has("shot"):
					# With a screen (not headless): what the plot looks like, to check the drawing.
					get_viewport().get_texture().get_image().save_png(_args["shot"])
				_phase = "measure"
				_measure_until = now + int(float(_args.get("seconds", "15")) * 1_000_000)
				_last = now
		"measure":
			if _args.has("walk") and (_plot.get("_path") as PackedVector2Array).is_empty():
				var start := Vector2(float(_args.get("tile_x", "20")), float(_args.get("tile_y", "30"))) + Vector2(0.5, 0.5)
				var far := start + Vector2(float(_args["walk"]), 0)
				var floor_pos: Vector2 = _plot.get("_player").get("floor_pos")
				_plot.set("_path", PackedVector2Array([far if floor_pos.distance_to(start) < floor_pos.distance_to(far) else start]))
			_frames.append((now - _last) / 1000.0)
			_scripts.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_last = now
			if now >= _measure_until:
				_report()
				_phase = "done"
				get_tree().quit()


func _report() -> void:
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	var scripts := 0.0
	for s in _scripts:
		scripts += s
	print("BENCH drawing commands %d, objects %d in the last frame" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	print("BENCH scripts per frame %.2f ms" % (scripts / _scripts.size()))
	if _args.has("walk"):
		print("BENCH walked to ", _plot.get("_player").get("floor_pos"), ", chunks drawn ", (_plot.get("_chunks") as Dictionary).size())
	var logistics: Variant = _plot.get("_logistics")
	print("BENCH frames %d, mean %.2f ms, median %.2f ms, p95 %.2f ms, p99 %.2f ms, worst %.1f ms; load %.0f ms, again %.0f ms; belts %d, inserters %d" % [
		_frames.size(), total / _frames.size(), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)],
		sorted[int(sorted.size() * 0.99)], sorted[-1], _args.get("loaded", 0.0), _args.get("again", 0.0),
		(logistics.get("_belts") as Dictionary).size(), (logistics.get("_inserters") as Dictionary).size()])
