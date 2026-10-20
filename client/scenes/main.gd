extends Control
## Start screen: waits for the server, then hands over to Game.start().

@onready var _status: Label = %Status
@onready var _latency: Label = %Latency


func _ready() -> void:
	Net.disconnected.connect(_on_disconnected)
	Net.message_received.connect(_on_message)
	_status.text = "Łączenie z serwerem..."
	_latency.text = ""


func _on_disconnected() -> void:
	_status.text = "Brak połączenia z serwerem, ponawiam..."


func _on_message(type: String, payload: Variant, _id: String) -> void:
	match type:
		"welcome":
			print("Połączono z serwerem (protokół %d)" % payload["protocol"])
			Game.start()
		"error":
			_status.text = "Błąd: %s" % payload["message"]
