class_name InputSetup
extends RefCounted
## Zentrale Tastenbelegung. Wird beim Start registriert (statt im project.godot),
## damit sie an einer Stelle lesbar, testbar und später im Einstellungsmenü änderbar ist.
##
## Steuerung im MOBA-Stil (Entscheidung des Spielers): Bewegen und Angreifen mit der Maus,
## Fähigkeiten auf Q W E R (R = Ultimate) sowie D und F.

const KEYS := {
	"ability_1": [KEY_Q],
	"ability_2": [KEY_W],
	"ability_3": [KEY_E],
	"ability_4": [KEY_R],
	"ability_5": [KEY_D],
	"ability_6": [KEY_F],
	"item_1": [KEY_1],
	"item_2": [KEY_2],
	"attack_move": [KEY_A],
	"stop": [KEY_S],
	"open_shop": [KEY_B],
	"open_inventory": [KEY_I],
	"open_character": [KEY_C],
	"team_overview": [KEY_TAB],
	"pause": [KEY_ESCAPE],
	"camera_center": [KEY_SPACE],
	"camera_lock": [KEY_Y],
	"call_wave": [KEY_N],
}

const MOUSE := {
	"primary_action": [MOUSE_BUTTON_LEFT],
	"secondary_action": [MOUSE_BUTTON_RIGHT],
	"zoom_in": [MOUSE_BUTTON_WHEEL_UP],
	"zoom_out": [MOUSE_BUTTON_WHEEL_DOWN],
}


static func register() -> void:
	for action in KEYS:
		_reset(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		_reset(action)
		for button in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)


static func _reset(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
