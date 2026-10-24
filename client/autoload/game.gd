extends Node
## Player session: login token, character and moving between screens.

const SESSION_FILE := "user://session.cfg"

const LOGIN_SCENE := "res://scenes/login.tscn"
const EDITOR_SCENE := "res://scenes/editor.tscn"
const GARAGE_SCENE := "res://scenes/garage.tscn"
const WORLD_MAP_SCENE := "res://scenes/world_map.tscn"
const PLOT_SCENE := "res://scenes/plot.tscn"

## Server error codes shown to the player in Polish.
const ERRORS := {
	"disconnected": "Brak połączenia z serwerem.",
	"invalid_email": "Nieprawidłowy adres e-mail.",
	"weak_password": "Hasło musi mieć od 8 do 128 znaków.",
	"email_taken": "Konto z tym adresem e-mail już istnieje.",
	"invalid_credentials": "Zły e-mail lub hasło.",
	"too_many_attempts": "Za dużo nieudanych prób. Odśwież grę i spróbuj ponownie.",
	"session_expired": "Sesja wygasła. Zaloguj się ponownie.",
	"invalid_name": "Nazwa: 3–16 znaków, litery, cyfry lub _.",
	"name_taken": "Ta nazwa jest już zajęta.",
	"invalid_appearance": "Nieznana opcja wyglądu.",
	"character_exists": "To konto ma już postać.",
	"no_character": "Najpierw stwórz postać.",
	"not_enough_items": "Nie masz tylu przedmiotów.",
	"not_enough_money": "Nie masz tyle pieniędzy.",
	"queue_full": "Kolejka segregacji jest pełna.",
	"bad_quantity": "Nieprawidłowa ilość.",
	"not_traded": "Handlarz nie handluje tym przedmiotem.",
	"unknown_item": "Nieznany przedmiot.",
	"no_bin": "Najpierw postaw w garażu kosz na śmieci.",
	"not_placeable": "Tego nie da się tu postawić.",
	"bad_position": "To się tu nie zmieści.",
	"blocked": "To miejsce jest zajęte.",
	"no_object": "Tego już tu nie ma.",
	"bad_plot": "Nie ma takiej działki.",
	"not_buyable": "Wody nie da się kupić.",
	"plot_taken": "Ktoś już kupił tę działkę.",
	"not_owner": "To nie jest twoja działka.",
	"wrong_tool": "Potrzebujesz innego narzędzia.",
	"nothing_here": "Tego już tu nie ma.",
	"too_fast": "Powoli, jeszcze nie skończyłeś.",
	"not_a_tool": "To nie jest narzędzie.",
	"bad_destination": "Wybierz inną działkę jako cel.",
	"no_station": "Na tej działce nie ma stacji (nikt jej nie kupił).",
	"not_fertile": "Orać można tylko żyzne gleby.",
	"unknown_crop": "Nieznana roślina.",
	"no_field": "Najpierw zaorz tu ziemię motyką.",
	"not_ripe": "To jeszcze nie dojrzało.",
	"no_mine": "Na tej działce nie ma takiej kopalni.",
	"mine_empty": "Kopalnia jest wyczerpana, odnowi się za chwilę.",
	"mine_max_level": "Ta kopalnia jest już rozbudowana do końca.",
	"already_surveyed": "Ta działka jest już zbadana.",
	"no_offer": "Tej oferty już nie ma.",
	"own_offer": "To twoja własna oferta.",
	"not_enough_offered": "W ofercie zostało mniej sztuk.",
	"too_many_offers": "Możesz mieć najwyżej 20 otwartych ofert każdego rodzaju.",
	"bad_price": "Cena musi wynosić od 0,01 $ do 1 000 000 $.",
	"no_recipe": "Nie ma takiego przepisu.",
	"crafting_queue_full": "Przy stole czeka już 5 zamówień.",
	"no_order": "Tego zamówienia już nie ma.",
	"furnace_busy": "W piecu przetapia się inna ruda. Wyjmij ją najpierw.",
	"furnace_full": "Tyle się nie zmieści w piecu.",
	"not_smeltable": "Tego nie da się włożyć do pieca.",
	"choose_recipe": "Najpierw wybierz, co ma powstawać.",
	"machine_full": "Tyle się nie zmieści w maszynie.",
	"machine_busy": "Przy ogniu leży już inne paliwo. Wyjmij je najpierw.",
	"not_processable": "Tego nie da się tu włożyć.",
	"no_contract": "Tego zlecenia już nie ma.",
	"own_contract": "To twoje własne zlecenie.",
	"contract_taken": "Ktoś inny już realizuje to zlecenie.",
	"contract_expired": "Termin tego zlecenia minął.",
	"not_contractor": "Najpierw przyjmij to zlecenie.",
	"too_many_contracts": "Możesz mieć najwyżej 10 otwartych zleceń.",
	"too_many_taken": "Naraz możesz realizować najwyżej 5 zleceń innych graczy.",
	"bad_reward": "Nagroda musi wynosić od 0,01 $ do 10 000 000 $.",
	"bad_deadline": "Termin: od 1 do 168 godzin.",
}

var token := ""
## Palettes and option counts of the character editor, from the server.
var appearance_options := {}
## The logged-in player's character, as sent by the server, or empty.
var character := {}
## The plot the player is on or last left, so the world map opens there; (-1, -1) if none.
var plot := Vector2i(-1, -1)


func _ready() -> void:
	get_tree().root.theme = UI.theme()
	add_child(ItemTooltip.new())
	var config := ConfigFile.new()
	if config.load(SESSION_FILE) == OK:
		token = config.get_value("session", "token", "")
	Net.connected.connect(_on_reconnected)


func error_text(reply: Dictionary) -> String:
	var payload: Variant = reply.get("payload")
	var code: String = payload.get("code", "") if payload is Dictionary else ""
	return ERRORS.get(code, "Błąd serwera (%s)." % code)


## Called by the start screen once connected: logs in with the saved token or shows the login screen.
func start() -> void:
	if appearance_options.is_empty():
		var options := await Net.request("character.options")
		if options["type"] == "character.options":
			appearance_options = options["payload"]

	if token != "":
		var reply := await Net.request("auth.resume", {"token": token})
		if reply["type"] == "auth.ok":
			await enter_game()
			return
		_save_token("")

	get_tree().change_scene_to_file(LOGIN_SCENE)


## Stores the session from an "auth.ok" reply and opens the right screen.
func logged_in(reply: Dictionary) -> void:
	_save_token(reply["payload"]["token"])
	await enter_game()


## Goes to the garage, or to the character editor when the account has no character yet.
func enter_game() -> void:
	var reply := await Net.request("character.get")
	if reply["type"] == "character":
		character = reply["payload"]
		get_tree().change_scene_to_file(GARAGE_SCENE)
	else:
		character = {}
		get_tree().change_scene_to_file(EDITOR_SCENE)


func open_garage() -> void:
	get_tree().change_scene_to_file(GARAGE_SCENE)


func open_world_map() -> void:
	get_tree().change_scene_to_file(WORLD_MAP_SCENE)


## Walks onto one of the player's plots.
func enter_plot(at: Vector2i) -> void:
	plot = at
	get_tree().change_scene_to_file(PLOT_SCENE)


## The tool in the player's hand: {id, name}, or empty.
func tool() -> Dictionary:
	var held: Variant = character.get("tool")
	return held if held is Dictionary else {}


## Applies an XP gain from the server ({ xp, level }); level thresholds follow 200 × (L − 1)².
func gain_xp(gain: Dictionary) -> void:
	var level: int = gain["level"]
	character["xp"] = gain["xp"]
	character["level"] = level
	character["levelXp"] = 200 * (level - 1) * (level - 1)
	character["nextLevelXp"] = 200 * level * level


func logout() -> void:
	await Net.request("auth.logout", {"token": token})
	_save_token("")
	character = {}
	get_tree().change_scene_to_file(LOGIN_SCENE)


## After a dropped connection, logs back in quietly so the player stays where they were.
func _on_reconnected() -> void:
	var scene := get_tree().current_scene
	if token == "" or scene == null or scene.scene_file_path == "res://scenes/main.tscn":
		return
	var reply := await Net.request("auth.resume", {"token": token})
	if reply["type"] != "auth.ok":
		_save_token("")
		get_tree().change_scene_to_file(LOGIN_SCENE)


func _save_token(value: String) -> void:
	token = value
	var config := ConfigFile.new()
	config.set_value("session", "token", value)
	config.save(SESSION_FILE)
