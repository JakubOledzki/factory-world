extends Control
## Login and registration.

var _email: LineEdit
var _password: LineEdit
var _error: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	var box := UI.centered_panel(self, 440)
	box.add_child(UI.title("Factory World"))
	box.add_child(UI.label("Zbuduj fabrykę od kosza na śmieci", UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	_email = UI.line_edit("E-mail")
	box.add_child(_email)
	_password = UI.line_edit("Hasło (min. 8 znaków)", true)
	_password.text_submitted.connect(func(_text: String) -> void: _submit("auth.login"))
	box.add_child(_password)

	_error = UI.label("", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true)
	_error.visible = false
	box.add_child(_error)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons = [
		UI.button("Zaloguj", _submit.bind("auth.login"), true),
		UI.button("Załóż konto", _submit.bind("auth.register")),
	]
	for b in _buttons:
		row.add_child(b)
	box.add_child(row)

	_email.grab_focus()


func _submit(type: String) -> void:
	_set_busy(true)
	_error.text = ""
	var reply := await Net.request(type, {"email": _email.text, "password": _password.text})
	if reply["type"] == "auth.ok":
		await Game.logged_in(reply)
		return
	_error.text = Game.error_text(reply)
	_error.visible = true
	_set_busy(false)


func _set_busy(busy: bool) -> void:
	for b in _buttons:
		b.disabled = busy
