extends Node
## Sounds and music. Effects answer what the player does (the server's replies to their requests,
## buttons, windows), the music follows the screen, and a quiet hum grows with the machines at work
## on the screen. Volumes are in Settings; the files come from tools/generate_audio.py.

## Request → effect played when the server answers it without an error.
const ON_REPLY := {
	"plot.harvest": "chop",
	"plot.mine": "mine",
	"meteor.dig": "mine",
	"plot.blast": "mine",
	"plot.reap": "harvest",
	"plot.plant": "harvest",
	"plot.plantTree": "harvest",
	"plot.till": "harvest",
	"farmstead.take": "harvest",
	"forester.take": "harvest",
	"plot.place": "place",
	"plot.placeMany": "place",
	"garage.place": "place",
	"plot.pickup": "pickup",
	"plot.pickupMany": "pickup",
	"plot.pickupArea": "pickup",
	"garage.pickup": "pickup",
	"plot.collect": "pickup",
	"market.sell": "coin",
	"market.buy": "coin",
	"market.purchase": "coin",
	"market.fill": "coin",
	"shop.take": "coin",
	"contracts.deliver": "coin",
	"city.deliver": "coin",
	"crafting.craft": "craft",
	"machine.recipe": "craft",
	"research.start": "craft",
	"station.send": "train",
	"expedition.send": "train",
	"album.claim": "achievement",
	"puzzle.submit": "research",
	"season.buy": "coin",
}
## Pushed messages → effect.
const ON_EVENT := {
	"achievement.unlocked": "achievement",
	"season.drop": "drop",
	"album.found": "drop",
}
const MUSIC := {
	"res://scenes/garage.tscn": "music_garage",
	"res://scenes/plot.tscn": "music_plot",
	"res://scenes/world_map.tscn": "music_world",
	"res://scenes/login.tscn": "music_garage",
	"res://scenes/editor.tscn": "music_garage",
}
## The same effect at most this often, so a burst of replies does not stack into noise.
const SAME_GAP := 0.06
const VOICES := 8
const FADE := 1.5

var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played := {}
var _music := AudioStreamPlayer.new()
var _music_track := ""
var _machines := AudioStreamPlayer.new()
var _machines_target := 0.0
var _scene := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	add_child(_music)
	add_child(_machines)
	_machines.stream = _load("loop_machines")
	_machines.volume_db = -80.0
	Net.replied.connect(_on_replied)
	Net.message_received.connect(_on_message)
	get_tree().node_added.connect(_on_node_added)
	Settings.changed.connect(_apply_volumes)
	_apply_volumes()


## Plays an effect by name (a file in res://audio/ without ".ogg").
func play(effect: String, volume_db := 0.0) -> void:
	if Settings.sfx_volume <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(effect, -1.0)) < SAME_GAP:
		return
	_last_played[effect] = now
	var stream := _load(effect)
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.volume_db = linear_to_db(Settings.sfx_volume) + volume_db
	voice.play()


## How many machines work on the screen now: the hum grows with them, up to a dozen.
func set_machines(count: int) -> void:
	_machines_target = clampf(count / 12.0, 0.0, 1.0)


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene != null else ""
	if path != _scene:
		_scene = path
		_switch_music(MUSIC.get(path, ""))
		if path != "res://scenes/plot.tscn":
			_machines_target = 0.0
	# The music fades in after a change of track; the hum follows the machines slowly.
	var music_db := linear_to_db(maxf(Settings.music_volume, 0.0001))
	if _music.playing and _music.volume_db < music_db:
		_music.volume_db = minf(music_db, _music.volume_db + 40.0 * delta / FADE)
	elif _music.playing:
		_music.volume_db = music_db
	var level := _machines_target * Settings.sfx_volume * 0.35
	var target_db := linear_to_db(maxf(level, 0.0001))
	_machines.volume_db = move_toward(_machines.volume_db, target_db, 30.0 * delta)
	if level > 0.0 and not _machines.playing:
		_machines.play()
	elif level <= 0.0 and _machines.playing and _machines.volume_db <= -60.0:
		_machines.stop()


func _switch_music(track: String) -> void:
	if track == _music_track:
		return
	_music_track = track
	_music.stop()
	if track == "" or Settings.music_volume <= 0.0:
		return
	_music.stream = _load(track)
	_music.volume_db = -40.0
	_music.play()


func _apply_volumes() -> void:
	if Settings.music_volume <= 0.0:
		_music.stop()
	elif not _music.playing and _music_track != "":
		var track := _music_track
		_music_track = ""
		_switch_music(track)


func _load(effect: String) -> AudioStream:
	if not _streams.has(effect):
		var path := "res://audio/%s.ogg" % effect
		var stream: AudioStreamOggVorbis = load(path) if ResourceLoader.exists(path) else null
		if stream != null and (effect.begins_with("music_") or effect.begins_with("loop_")):
			stream.loop = true
		_streams[effect] = stream
	return _streams[effect]


func _on_replied(request_type: String, reply: Dictionary) -> void:
	if reply.get("type") == "error":
		var code: Variant = reply["payload"].get("code") if reply.get("payload") is Dictionary else null
		if code != "disconnected":
			play("error", -4.0)
		return
	var payload: Variant = reply.get("payload")
	if payload is Dictionary and payload.get("xp") is Dictionary and payload["xp"].get("leveledUp", false):
		play("levelup")
		return
	if ON_REPLY.has(request_type):
		play(ON_REPLY[request_type])


func _on_message(type: String, _payload: Variant, id: String) -> void:
	if id == "" and ON_EVENT.has(type):
		play(ON_EVENT[type])


## Every button clicks.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("click", -6.0))
