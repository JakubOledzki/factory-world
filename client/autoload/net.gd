extends Node
## Connection to the game server. One JSON envelope per WebSocket message:
## { "type": "...", "id": "...", "payload": { ... } }

signal connected
signal disconnected
signal message_received(type: String, payload: Variant, id: String)

const PROTOCOL_VERSION := 1
const RECONNECT_DELAY := 3.0

var _socket := WebSocketPeer.new()
var _last_state := WebSocketPeer.STATE_CLOSED
var _next_id := 0
var _reconnect_in := 0.0


func _ready() -> void:
	connect_to_server()


func server_url() -> String:
	# In the browser the game is served by the same host as the server, behind one domain.
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval(
			"(location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws'"))
	return ProjectSettings.get_setting("factory_world/server_url", "ws://localhost:5080/ws")


func connect_to_server() -> void:
	var err := _socket.connect_to_url(server_url())
	if err != OK:
		push_warning("Cannot connect to %s (error %d)" % [server_url(), err])
		_reconnect_in = RECONNECT_DELAY


func is_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


## Sends a request and returns its id, so the reply can be matched.
func send(type: String, payload: Variant = null) -> String:
	_next_id += 1
	var id := str(_next_id)
	var envelope := {"type": type, "id": id}
	if payload != null:
		envelope["payload"] = payload
	_socket.send_text(JSON.stringify(envelope))
	return id


func _process(delta: float) -> void:
	if _reconnect_in > 0.0:
		_reconnect_in -= delta
		if _reconnect_in <= 0.0:
			connect_to_server()
		return

	_socket.poll()
	var state := _socket.get_ready_state()

	if state != _last_state:
		_last_state = state
		if state == WebSocketPeer.STATE_OPEN:
			send("hello", {"protocol": PROTOCOL_VERSION})
			connected.emit()
		elif state == WebSocketPeer.STATE_CLOSED:
			disconnected.emit()
			_reconnect_in = RECONNECT_DELAY

	while state == WebSocketPeer.STATE_OPEN and _socket.get_available_packet_count() > 0:
		_handle_packet(_socket.get_packet().get_string_from_utf8())


func _handle_packet(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or not data.has("type"):
		push_warning("Bad message from server: %s" % text)
		return
	var id: String = data.get("id") if data.get("id") != null else ""
	message_received.emit(data["type"], data.get("payload"), id)
