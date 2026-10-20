extends Control
## Stage 0 screen: shows whether the client talks to the server.

const PING_INTERVAL := 5.0

@onready var _status: Label = %Status
@onready var _latency: Label = %Latency

var _ping_sent_at := {}
var _ping_in := 0.0


func _ready() -> void:
	Net.connected.connect(_on_connected)
	Net.disconnected.connect(_on_disconnected)
	Net.message_received.connect(_on_message)
	_status.text = "Łączenie z %s..." % Net.server_url()


func _process(delta: float) -> void:
	if not Net.is_open():
		return
	_ping_in -= delta
	if _ping_in <= 0.0:
		_ping_in = PING_INTERVAL
		_ping_sent_at[Net.send("ping")] = Time.get_ticks_msec()


func _on_connected() -> void:
	_status.text = "Połączono, witamy..."


func _on_disconnected() -> void:
	_status.text = "Brak połączenia z serwerem, ponawiam..."
	_latency.text = ""


func _on_message(type: String, payload: Variant, id: String) -> void:
	match type:
		"welcome":
			_status.text = "Połączono z serwerem (protokół %d)" % payload["protocol"]
			print(_status.text)
		"pong":
			if _ping_sent_at.has(id):
				_latency.text = "Ping: %d ms" % (Time.get_ticks_msec() - _ping_sent_at[id])
				print(_latency.text)
				_ping_sent_at.erase(id)
		"error":
			_status.text = "Błąd: %s" % payload["message"]
