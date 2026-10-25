extends Node
## Connection to the game server. One JSON envelope per WebSocket message:
## { "type": "...", "id": "...", "payload": { ... } }

signal connected
signal disconnected
signal message_received(type: String, payload: Variant, id: String)

const PROTOCOL_VERSION := 1
const RECONNECT_DELAY := 3.0

## One request waiting for its reply.
class Pending:
	signal done(reply: Dictionary)
	## The reply once it came, for whoever waits for it after it did (see request_all).
	var reply := {}
	var finished := false

	func finish(with: Dictionary) -> void:
		reply = with
		finished = true
		done.emit(with)


var _socket := WebSocketPeer.new()
var _pending := {}
var _last_state := WebSocketPeer.STATE_CLOSED
var _next_id := 0
var _reconnect_in := 0.0


func _ready() -> void:
	# A plot's tiles come in one message of up to a few hundred kilobytes.
	_socket.inbound_buffer_size = 1 << 20
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


## Sends a request and waits for its reply: {"type": ..., "payload": ...}.
## Usage: var reply := await Net.request("auth.login", {...})
func request(type: String, payload: Variant = null) -> Dictionary:
	if not is_open():
		return _disconnected_reply()
	var pending := Pending.new()
	_pending[send(type, payload)] = pending
	var reply: Dictionary = await pending.done
	return reply


## Sends several requests at once and waits for all their replies, in the same order: [[type, payload], ...].
## The server still answers them one after another, but they need one trip over the network instead of one each.
func request_all(requests: Array) -> Array[Dictionary]:
	var waiting: Array[Pending] = []
	for r: Array in requests:
		var pending := Pending.new()
		if is_open():
			_pending[send(r[0], r[1] if r.size() > 1 else null)] = pending
		else:
			pending.finish(_disconnected_reply())
		waiting.append(pending)
	var replies: Array[Dictionary] = []
	for pending in waiting:
		if not pending.finished:
			await pending.done
		replies.append(pending.reply)
	return replies


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
			_fail_pending()
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
	if _pending.has(id):
		var pending: Pending = _pending[id]
		_pending.erase(id)
		pending.finish({"type": data["type"], "payload": data.get("payload")})
	message_received.emit(data["type"], data.get("payload"), id)


func _fail_pending() -> void:
	var waiting := _pending.values()
	_pending.clear()
	for pending: Pending in waiting:
		pending.finish(_disconnected_reply())


func _disconnected_reply() -> Dictionary:
	return {"type": "error", "payload": {"code": "disconnected", "message": "Not connected."}}
