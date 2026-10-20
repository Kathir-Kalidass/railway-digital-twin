extends Node

var last_control_type: int = ControlType.Keyboard

signal control_type_changed()


func _unhandled_input(event) -> void:
	if event is InputEventKey or event is InputEventMouse \
			and last_control_type != ControlType.Keyboard:
		last_control_type = ControlType.Keyboard
		emit_signal("control_type_changed")
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion \
			and !(last_control_type & ControlType.Joypad):
		match Input.get_joy_guid(event.device):
			"__XINPUT_DEVICE__":
				last_control_type = ControlType.XBox
			"030000004c050000cc09000000000000":
				last_control_type = ControlType.Playstation
			_:
				print("Unknown input device (Please report): ", Input.get_joy_guid(event.device))
				last_control_type = ControlType.Joypad
		emit_signal("control_type_changed")


# input: array of actions (strings), eg ["acc+", "acc-"]
# output: array of buttons (strings), eg ["W", "S"]
func make_strings_from_actions(actions: Array) -> Array:
	var controls := []
	for action in actions:
		assert(InputMap.has_action(action))
		var found_event := false
		for event in InputMap.action_get_events(action):
			if last_control_type == ControlType.Keyboard and event is InputEventKey:
				controls.push_back(event.as_text())
				found_event = true
				break
			elif last_control_type & ControlType.Joypad and event is InputEventJoypadButton:
				controls.push_back(get_joy_button_name(event.button_index))
				found_event = true
				break
			elif last_control_type & ControlType.Joypad and event is InputEventJoypadMotion:
				controls.push_back(get_joy_axis_name(event.axis))
				found_event = true
				break
		if !found_event:
			controls.push_back("n/a")
	return controls # if you get a debug break here, the position is broken


func get_joy_button_name(button_index: int) -> String:
	if last_control_type == ControlType.Playstation:
		return _get_playstation_button_name(button_index)
	else: # we don't know what the controller is. XBox is probably more common on desktops
		return _get_xbox_button_name(button_index)


func get_joy_axis_name(axis: int) -> String:
	if last_control_type == ControlType.Playstation:
		return _get_playstation_axis_name(axis)
	else: # we don't know what the controller is. XBox is probably more common on desktops
		return _get_xbox_axis_name(axis)


func _get_xbox_button_name(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_STICK:
			return "Left Stick"
		JOY_BUTTON_RIGHT_STICK:
			return "Right Stick"
		JOY_BUTTON_DPAD_UP:
			return "DPAD Up"
		JOY_BUTTON_DPAD_DOWN:
			return "DPAD Down"
		JOY_BUTTON_DPAD_LEFT:
			return "DPAD Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "DPAD Right"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		_:
			assert(false) # Add button to list above
			return "n/a"


func _get_playstation_button_name(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A:
			return "X"
		JOY_BUTTON_B:
			return "Circle"
		JOY_BUTTON_X:
			return "Square"
		JOY_BUTTON_Y:
			return "Triangle"
		JOY_BUTTON_LEFT_STICK:
			return "Left Stick"
		JOY_BUTTON_RIGHT_STICK:
			return "Right Stick"
		JOY_BUTTON_DPAD_UP:
			return "DPAD Up"
		JOY_BUTTON_DPAD_DOWN:
			return "DPAD Down"
		JOY_BUTTON_DPAD_LEFT:
			return "DPAD Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "DPAD Right"
		JOY_BUTTON_BACK:
			return "Share"
		JOY_BUTTON_START:
			return "Options"
		JOY_BUTTON_LEFT_SHOULDER:
			return "L1"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "R1"
		_:
			assert(false) # Add button to list above
			return "n/a"


func _get_xbox_axis_name(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left Stick Horizontal"
		JOY_AXIS_LEFT_Y:
			return "Left Stick Vertical"
		JOY_AXIS_RIGHT_X:
			return "Right Stick Horizontal"
		JOY_AXIS_RIGHT_Y:
			return "Right Stick Vertical"
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		_:
			assert(false) # Add button to list above
			return "n/a"


func _get_playstation_axis_name(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "Left Stick Horizontal"
		JOY_AXIS_LEFT_Y:
			return "Left Stick Vertical"
		JOY_AXIS_RIGHT_X:
			return "Right Stick Horizontal"
		JOY_AXIS_RIGHT_Y:
			return "Right Stick Vertical"
		JOY_AXIS_TRIGGER_LEFT:
			return "L2"
		JOY_AXIS_TRIGGER_RIGHT:
			return "R2"
		_:
			assert(false) # Add button to list above
			return "n/a"
