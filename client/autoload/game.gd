extends Node
## Player session: login token, character and moving between screens.

const SESSION_FILE := "user://session.cfg"

const LOGIN_SCENE := "res://scenes/login.tscn"
const EDITOR_SCENE := "res://scenes/editor.tscn"
const GARAGE_SCENE := "res://scenes/garage.tscn"
const WORLD_MAP_SCENE := "res://scenes/world_map.tscn"
const PLOT_SCENE := "res://scenes/plot.tscn"
## The highest level a character reaches, as on the server.
const MAX_LEVEL := 100

## Server error codes shown to the player in Polish.
const ERRORS := {
	"disconnected": "Brak połączenia z serwerem.",
	"invalid_email": "Nieprawidłowy adres e-mail.",
	"weak_password": "Hasło musi mieć od 8 do 128 znaków.",
	"email_taken": "Konto z tym adresem e-mail już istnieje.",
	"invalid_credentials": "Zły e-mail lub hasło.",
	"too_many_attempts": "Za dużo nieudanych prób. Odśwież grę i spróbuj ponownie.",
	"session_expired": "Sesja wygasła. Zaloguj się ponownie.",
	"logged_in_elsewhere": "Zalogowano się na to konto na innym urządzeniu albo w innej karcie, więc tutaj gra została wylogowana. Konto może grać tylko w jednym miejscu naraz.",
	"invalid_name": "Nazwa: 3–16 znaków, litery, cyfry lub _.",
	"name_taken": "Ta nazwa jest już zajęta.",
	"invalid_appearance": "Nieznana opcja wyglądu.",
	"same_look": "To jest twój obecny wygląd. Zmień coś, zanim zapłacisz.",
	"character_exists": "To konto ma już postać.",
	"no_character": "Najpierw stwórz postać.",
	"not_enough_items": "Nie masz tylu przedmiotów.",
	"inventory_full": "Ekwipunek pełny. Zrób miejsce albo załóż większy plecak (kupisz go u handlarza).",
	"bad_slot": "Nie ma takiego miejsca.",
	"bad_hotbar_slot": "Pasek ma tylko sloty od 1 do 5.",
	"not_enough_money": "Nie masz tyle pieniędzy.",
	"queue_full": "Kolejka segregacji jest pełna.",
	"no_upgrade": "Nie ma takiego ulepszenia.",
	"no_garage": "Najpierw otwórz swój garaż.",
	"max_level": "To ulepszenie jest już na najwyższym poziomie.",
	"upgrade_required": "Najpierw kup wymagane ulepszenie.",
	"storage_full": "Tu już nic się nie zmieści. Ulepsz regały, żeby mieć więcej miejsca.",
	"not_clothing": "Do szafy wkładasz tylko ubrania.",
	"missing_clothes": "Brakuje części kompletu: nie ma jej ani w szafie, ani w ekwipunku.",
	"no_outfit": "Ten komplet nie jest zapisany.",
	"bad_outfit": "Nie ma takiego kompletu.",
	"bad_name": "Nazwa kompletu może mieć najwyżej 20 znaków.",
	"bad_quantity": "Nieprawidłowa ilość.",
	"not_traded": "Handlarz nie handluje tym przedmiotem.",
	"unknown_item": "Nieznany przedmiot.",
	"no_bin": "Najpierw postaw w garażu kosz na śmieci.",
	"not_placeable": "Tego nie da się tu postawić.",
	"bad_position": "To się tu nie zmieści.",
	"blocked": "To miejsce jest zajęte.",
	"no_object": "Tego już tu nie ma.",
	"not_stored_here": "Tu tego nie przyjmie: magazyn bierze inne rzeczy albo ma ustawiony filtr na inny przedmiot.",
	"not_filterable": "Temu nie ustawisz filtra.",
	"bad_filter": "Nie ma takiego przedmiotu.",
	"bad_plot": "Nie ma takiej działki.",
	"not_buyable": "Wody nie da się kupić.",
	"plot_taken": "Ktoś już kupił tę działkę.",
	"not_owner": "To nie jest twoja działka albo twoja rola w spółce na to nie pozwala.",
	"not_yours": "To postawił ktoś inny. Podnieść to może on albo właściciel działki.",
	"invalid_company_name": "Nazwa spółki: 3–24 znaki, litery, cyfry lub spacje.",
	"company_name_taken": "Spółka o tej nazwie już istnieje.",
	"already_in_company": "Ten gracz (albo ty) jest już w spółce.",
	"no_such_player": "Nie ma gracza o takiej nazwie.",
	"company_full": "Spółka ma już komplet członków.",
	"no_invite": "Ta spółka cię nie zaprosiła.",
	"no_company": "Nie należysz do spółki.",
	"not_allowed": "Twoja rola w spółce na to nie pozwala.",
	"hand_over_first": "Najpierw przekaż prezesurę innemu członkowi.",
	"not_member": "Tego gracza nie ma w twojej spółce.",
	"not_yourself": "Tego nie możesz zrobić sam sobie.",
	"bad_role": "Nieznana rola.",
	"warehouse_full": "W magazynie spółki nie ma już miejsca.",
	"wrong_tool": "Potrzebujesz innego narzędzia.",
	"nothing_here": "Tego już tu nie ma.",
	"too_fast": "Powoli, jeszcze nie skończyłeś.",
	"not_a_tool": "To nie jest narzędzie.",
	"bad_destination": "Wybierz inną działkę jako cel.",
	"no_station": "Na tej działce nie ma stacji (nikt jej nie kupił).",
	"bad_interval": "Pociąg może odjeżdżać co 1, 5, 15 albo 60 minut.",
	"bad_items": "Kurs może wozić najwyżej 8 rodzajów towaru.",
	"too_many_routes": "Ze stacji odjeżdża już tyle kursów, ile może (5, a z terminalem przeładunkowym w mieście 10).",
	"no_route": "Tego kursu już nie ma.",
	"not_fertile": "Orać, a zagrodę rolnika stawiać, można tylko na żyznej ziemi (pola uprawne, oaza).",
	"unknown_crop": "Nieznana roślina.",
	"no_field": "Najpierw zaorz tu ziemię motyką.",
	"no_forestry": "Na lodowcu i w górach drzewa nie rosną: nie da się tu sadzić ani stawiać budynków leśnika.",
	"not_ripe": "To jeszcze nie dojrzało.",
	"reap_first": "Najpierw zbierz to, co dojrzało na tym polu.",
	"farmstead_field": "To pole należy do zagrody rolnika: zniknie razem z nią, gdy ją schowasz.",
	"no_mine": "Na tej działce nie ma takiej kopalni.",
	"mine_empty": "Kopalnia jest wyczerpana, odnowi się za chwilę.",
	"mine_max_level": "Ta kopalnia jest już rozbudowana do końca.",
	"no_mine_here": "Wiertło musi stać tuż przy kopalni.",
	"mine_has_drill": "Przy tej kopalni stoi już wiertło: jedno na kopalnię.",
	"no_quarry": "Kamieniołom stawia się tylko w górach.",
	"no_water": "Koło wodne i elektrownia wodna potrzebują wody: postaw je w górach, nad jeziorem albo na wybrzeżu.",
	"storm": "Sztorm! Wędką łowisz w sztorm tylko z falochronu; łodzie stoją w porcie, aż przejdzie.",
	"no_coast": "To stawia się tylko na wybrzeżu morza.",
	"no_lake": "To stawia się tylko nad jeziorem, na pojezierzu.",
	"no_shore": "To stawia się tylko nad morzem albo jeziorem.",
	"not_on_shore": "To stoi na brzegu: postaw je tuż przy wodzie.",
	"too_many_boats": "Na jednej działce mieszczą się najwyżej 4 łodzie.",
	"overfished": "Ta woda jest przełowiona: na działkach dookoła stoi już tyle łodzi, ile ryb starczy.",
	"no_port": "Statek płynie z przystani do przystani: obie działki muszą mieć przystań.",
	"no_fuel_needed": "Woda, słońce albo zgromadzony prąd: to nie spala opału.",
	"no_sand": "Elektrownię słoneczną z lustrami stawia się tylko na pustyni albo w oazie.",
	"buried": "To przysypała zaspa po zamieci: najpierw odkop śnieg łopatą.",
	"no_polar": "To działa tylko na lodowcu albo w tundrze; gdzie indziej wóz konny rusza ze stajni na działce.",
	"no_glacier": "To stawia się tylko na lodowcu.",
	"has_foundation": "Na tej działce leży już fundament torów.",
	"no_sled": "Sanie wyruszają z psiarni albo garażu skuterów: postaw jedno z nich na działce.",
	"no_petrol": "Skuter potrzebuje benzyny na stacji (1 sztuka na każde 50 km).",
	"not_boost": "Badania przyspieszają tylko dane badawcze i moc obliczeniowa.",
	"too_far": "Za daleko: sanie jadą najwyżej 150 km, a wóz konny 50 km.",
	"not_city": "Ta działka nie leży w mieście.",
	"no_city": "To stoi tylko na działce w mieście.",
	"city_cramped": "W mieście buduje się tylko przy stacji (30 pól w obie strony, do 60. rzędu).",
	"has_one": "Na działce zmieści się tylko jeden taki budynek.",
	"far_from_station": "Skrzynia eksportowa stoi przy stacji: najwyżej 3 pola od budynku albo toru.",
	"town_has_market": "W tym mieście stoi już rynek skupu: jeden na miasto.",
	"chest_full": "Skrzynia eksportowa mieści najwyżej 1600 sztuk 16 rodzajów.",
	"no_export_chest": "Na tej działce nie ma skrzyni eksportowej.",
	"bad_commission": "Prowizja wynosi od 0 do 20%.",
	"bad_fee": "Opłata za przeprawę wynosi od 0 do 1000 $.",
	"no_post": "Nie ma już takiego rynku skupu ani portu.",
	"not_wanted": "Miasto dziś tego nie potrzebuje.",
	"need_met": "Miasto ma już dziś tyle, ile chciało.",
	"no_trash": "Miasto nie ma już dziś śmieci do wywiezienia.",
	"no_service": "W tym mieście nie ma takiego biura.",
	"own_service": "To twoje biuro: zrób to sam.",
	"service_busy": "Biuro obsłużyło już dziś komplet klientów. Wróć jutro.",
	"not_townsman": "Głosują tylko właściciele działek w tym mieście.",
	"not_candidate": "Można głosować tylko na właściciela działki w tym mieście.",
	"not_mayor": "Podatek, premię i festyn ustala tylko burmistrz tego tygodnia.",
	"bad_tax": "Podatek wynosi od 0 do 10%.",
	"bad_bonus": "Nie ma takiej premii.",
	"no_shop": "Nie ma takiego sklepu.",
	"not_sellable": "Nikt w mieście tego nie kupi.",
	"shop_full": "Sklep mieści najwyżej 8 rodzajów towaru.",
	"hq_off_company": "Siedziba stoi tylko na działce wniesionej do twojej spółki.",
	"bad_sapling": "To nie jest sadzonka.",
	"bad_feed": "To zwierzę tego nie je. Koń roboczy je tylko paszę treściwą.",
	"banquet_needed": "Potrzeba wykwintnych dań w magazynie lub ekwipunku: pieczeni wołowej albo sernika (bankiet na giełdę: 200, festyn: 100).",
	"canteen_full": "Stołówka ma już jedzenie na 48 godzin.",
	"farmstead_full": "Zagroda mieści najwyżej 50 obornika.",
	"feeder_full": "Karmnik jest pełny (najwyżej 60 sztuk paszy).",
	"no_feed": "Konie potrzebują paszy treściwej na stacji (1 sztuka na każde 10 km).",
	"no_stable": "Konia wypuścisz tylko na działce ze stajnią.",
	"not_a_meal": "Tego nie zjesz w biegu. Spróbuj chleba, kanapki z serem albo gulaszu drwala.",
	"not_food": "Stołówka tego nie wydaje.",
	"no_bees": "Pszczoły nie latają na lodowcu ani w górach.",
	"company_only": "Tę technologię bada tylko spółka, razem.",
	"company_short": "W kasie spółki nie ma tyle pieniędzy.",
	"bad_amount": "Podaj poprawną kwotę.",
	"not_bought": "Handlarz tego nie kupuje.",
	"not_sold": "Handlarz tego nie sprzedaje.",
	"bad_percent": "Dywidenda to od 0 do 100% zarobku.",
	"not_company_plot": "Ta działka nie należy do twojej spółki.",
	"research_needed": "Spółka musi to najpierw zbadać.",
	"not_listed": "Tej spółki nie ma na giełdzie.",
	"not_enough_shares": "Nie masz tylu akcji.",
	"no_majority": "Do przejęcia potrzeba ponad połowy akcji.",
	"already_owner": "Już kierujesz tą spółką.",
	"no_project": "Nie ma takiego projektu.",
	"project_started": "Spółka już podjęła się tego projektu.",
	"project_locked": "Spółka musi najpierw zbudować projekty, których ten wymaga.",
	"project_closed": "Spółka nie zbiera teraz części na ten projekt.",
	"not_needed": "Tego już nie potrzeba.",
	"order_done": "To zlecenie jest już wykonane.",
	"too_many_tasks": "Spółka ma najwyżej 20 otwartych zadań.",
	"not_your_task": "To zadanie jest dla kogoś innego.",
	"no_task": "Nie ma już takiego zadania.",
	"bad_deal": "Umowa trwa od 1 do 30 dni i obejmuje najwyżej 10 000 sztuk dziennie.",
	"no_such_company": "Nie ma innej spółki o tej nazwie.",
	"too_many_deals": "Spółka ma najwyżej 10 ofert i umów naraz.",
	"no_deal": "Nie ma takiej oferty dla twojej spółki.",
	"camel_sand": "Wielbłąd żyje tylko na pustyni i w oazie.",
	"no_pasture": "Tu nie wypasiesz tego zwierzęcia: na pustyni żyją tylko wielbłądy, a na lodowcu nic.",
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
	"sorter_full": "W sortowni zmieści się najwyżej 50 worków śmieci.",
	"no_sorter": "Tej sortowni nie ma już w garażu.",
	"not_smeltable": "Tego nie da się włożyć do pieca.",
	"choose_recipe": "Najpierw wybierz, co ma powstawać.",
	"machine_full": "Tyle się nie zmieści w maszynie.",
	"machine_busy": "Przy ogniu leży już inne paliwo. Wyjmij je najpierw.",
	"not_processable": "Tego nie da się tu włożyć.",
	"not_fuel": "Ten generator tego nie spali.",
	"generator_busy": "Przy ogniu leży już inny opał. Wyjmij go najpierw.",
	"generator_full": "Tyle opału nie zmieści się w generatorze.",
	"no_contract": "Tego zlecenia już nie ma.",
	"own_contract": "To twoje własne zlecenie.",
	"contract_taken": "Ktoś inny już realizuje to zlecenie.",
	"contract_expired": "Termin tego zlecenia minął.",
	"not_contractor": "Najpierw przyjmij to zlecenie.",
	"too_many_contracts": "Możesz mieć najwyżej 10 otwartych zleceń.",
	"too_many_taken": "Naraz możesz realizować najwyżej 5 zleceń innych graczy.",
	"bad_reward": "Nagroda musi wynosić od 0,01 $ do 10 000 000 $.",
	"bad_deadline": "Termin: od 1 do 168 godzin.",
	"locked": "Najpierw odblokuj to w drzewku technologii (stół badawczy w garażu).",
	"no_technology": "Nie ma takiej technologii.",
	"already_researched": "Ta technologia jest już zbadana.",
	"research_busy": "Trwa już inne badanie. Poczekaj albo je przerwij.",
	"research_locked": "Najpierw zbadaj technologie, których ta wymaga.",
	"no_research": "Nic się teraz nie bada.",
	"not_surveyed": "Najpierw zbadaj złoża tej działki (mapa świata, Badanie złóż).",
	"no_oil": "Badanie nie znalazło tu ropy.",
	"no_gas": "Badanie nie znalazło tu gazu.",
	"too_many_wells": "Na tym złożu stoi już tyle szybów, ile ono uniesie.",
	"polluted": "Ropa z cieknącego szybu zanieczyściła tu ziemię. Uszczelnij szyb albo postaw przy nim separator.",
	"no_gasket": "Nie masz uszczelki.",
	"well_full": "W szybie jest już komplet uszczelek.",
}

var token := ""
## Why the player was sent back to the login screen (e.g. logged in elsewhere), shown there once.
var logout_reason := ""
## Palettes and option counts of the character editor, from the server.
var appearance_options := {}
## After the character changed: its clothes, look, tools or backpack.
signal character_changed

## The logged-in player's character, as sent by the server, or empty.
var character := {}:
	set(value):
		character = value
		character_changed.emit()
## The plot the player is on or last left, so the world map opens there; (-1, -1) if none.
var plot := Vector2i(-1, -1)


func _ready() -> void:
	get_tree().root.theme = UI.theme()
	add_child(ItemTooltip.new())
	add_child(AchievementToast.new())
	var config := ConfigFile.new()
	if config.load(SESSION_FILE) == OK:
		token = config.get_value("session", "token", "")
	Net.connected.connect(_on_reconnected)
	Net.message_received.connect(_on_message)


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
		watch_achievements()
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


## The tool bar: one {id, name} or null per slot (one slot, two or three with a backpack on).
func tool_slots() -> Array:
	var slots: Variant = character.get("tools")
	return slots if slots is Array and not slots.is_empty() else [null]


## The tools in the tool bar, slot by slot, empty slots left out.
func tools() -> Array[Dictionary]:
	var held: Array[Dictionary] = []
	for tool: Variant in tool_slots():
		if tool is Dictionary:
			held.append(tool)
	return held


## Whether this tool is in the tool bar.
func holds(id: String) -> bool:
	return tools().any(func(t: Dictionary) -> bool: return t["id"] == id)


## The backpack worn: {id, name, extraSlots, toolSlots}, or empty.
func backpack() -> Dictionary:
	var worn: Variant = character.get("backpack")
	return worn if worn is Dictionary else {}


## The character's look for drawing: its appearance, with the clothes worn ({slot: item}) under "outfit".
func look() -> Dictionary:
	var drawn: Dictionary = character.get("appearance", {}).duplicate()
	var worn := {}
	var outfit: Variant = character.get("outfit")
	if outfit is Dictionary:
		for slot: String in outfit:
			worn[slot] = outfit[slot]["id"]
	drawn["outfit"] = worn
	return drawn


## Fetches the character again, e.g. after the server gave a tool.
func reload_character() -> void:
	var reply := await Net.request("character.get")
	if reply["type"] == "character":
		character = reply["payload"]


## Total XP to reach a level, as the server counts it: 200 × (L − 1)² + 4 × (L − 1)³.
static func xp_for_level(level: int) -> int:
	var n := level - 1
	return 200 * n * n + 4 * n * n * n


## Applies an XP gain from the server ({ xp, level }).
func gain_xp(gain: Dictionary) -> void:
	var level: int = gain["level"]
	character["xp"] = gain["xp"]
	character["level"] = level
	character["levelXp"] = xp_for_level(level)
	character["nextLevelXp"] = xp_for_level(level + 1) if level < MAX_LEVEL else null
	# A new level may bring a bonus (every fifth level), which the server adds to "bonuses".
	if gain.get("leveledUp", false):
		reload_character()


func logout() -> void:
	await Net.request("auth.logout", {"token": token})
	_save_token("")
	character = {}
	get_tree().change_scene_to_file(LOGIN_SCENE)


## The account logged in on another device or browser tab: the server closes this connection, and the
## game goes back to the login screen without logging in again by itself, so the two do not take turns.
## The saved token stays: another tab of the same browser plays with it now.
func _on_message(type: String, payload: Variant, _id: String) -> void:
	if type != "auth.kicked":
		return
	token = ""
	character = {}
	var code: String = payload.get("code", "") if payload is Dictionary else ""
	logout_reason = ERRORS.get(code, ERRORS["logged_in_elsewhere"])
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
	elif not character.is_empty():
		watch_achievements()


## From now on the server tells this connection of every badge the player unlocks (AchievementToast).
func watch_achievements() -> void:
	Net.send("achievements.watch")


func _save_token(value: String) -> void:
	token = value
	var config := ConfigFile.new()
	config.set_value("session", "token", value)
	config.save(SESSION_FILE)
