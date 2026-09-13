extends Control

# Logical points mirror DrumxSettingsPage. The app shell owns OS display scaling.
const Menu = preload("res://scripts/main_menu.gd")
const PAPER = Color(0.94, 0.95, 0.91, 1)
const LIME = Color(0.79, 0.91, 0.49, 1)
const MUTED = Color(0.57, 0.65, 0.64, 1)
const INK = Color(0.047, 0.063, 0.071, 1)
const CORAL = Color(0.96, 0.57, 0.47, 1)
const PAD_NAMES = ["Hi-hat", "Snare", "Kick"]

var controller: Object
# Wire these into the controller after add_child(), then refresh sources/mapping.
var kit_canvas: Control
var mapping_label: Label
var signal_label: Label
var source_option: OptionButton
var selected_section := 0

var _heading: Label
var _tabs: Array[Button] = []
var _panels: Array[Control] = []
var _centered_stacks: Array[Dictionary] = []
var _kit_details: VBoxContainer
var _mapping_title: Label
var _mapping_help: Label
var _receipt_status: Label
var _cancel_button: Button
var _learn_button: Button
var _monitor_toggle: Button
var _volume_slider: HSlider
var _volume_readout: Label
var _audio_status: Label
var _saved_takes: Label
var _saved_lesson: Label
var _retry_save_button: Button
var _refresh_elapsed := 0.0
var _fonts: Dictionary = {}
var _status_label: Label
var _body_scroll: ScrollContainer
var _body_content: Control


class SettingRow:
	extends Panel
	var copy: VBoxContainer
	var accessory: Control
	var accessory_width := 230.0

	func _ready() -> void:
		copy.minimum_size_changed.connect(func(): _layout_row.call_deferred())
		accessory.minimum_size_changed.connect(func(): _layout_row.call_deferred())
		_layout_row()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and copy != null and accessory != null:
			_layout_row()

	func _layout_row() -> void:
		copy.position.x = 0
		copy.size.x = maxf(120, size.x - accessory_width - 40)
		copy.size.y = copy.get_combined_minimum_size().y
		accessory.size = Vector2(accessory_width, maxf(44, accessory.get_combined_minimum_size().y))
		custom_minimum_size.y = maxf(96, maxf(copy.size.y, accessory.size.y) + 36)
		copy.position.y = maxf(18, (size.y - copy.size.y) / 2)
		accessory.position = Vector2(size.x - accessory_width, maxf(18, (size.y - accessory.size.y) / 2))


class SoundToggle:
	extends Button
	var copy_font: Font
	var hovered := false

	func _init() -> void:
		toggle_mode = true
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(230, 36)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		accessibility_name = "Drumx drum sounds"
		accessibility_description = "Play acoustic drum sounds when a pad is struck."
		tooltip_text = "Play Drumx sounds when you strike a pad."
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		toggled.connect(func(_value): queue_redraw())
		mouse_entered.connect(func(): hovered = true; queue_redraw())
		mouse_exited.connect(func(): hovered = false; queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		if copy_font == null: return
		var track := Rect2(0, (size.y - 24) / 2, 42, 24)
		var surface := StyleBoxFlat.new()
		surface.bg_color = Color("def3a5") if button_pressed and hovered else LIME if button_pressed else Color(PAPER, 0.2 if hovered else 0.12)
		surface.set_corner_radius_all(12)
		surface.draw(get_canvas_item(), track)
		draw_circle(Vector2(track.position.x + (30 if button_pressed else 12), size.y / 2), 8, INK if button_pressed else PAPER)
		if has_focus():
			var focus := StyleBoxFlat.new()
			focus.bg_color = Color.TRANSPARENT
			focus.border_color = LIME
			focus.set_border_width_all(1)
			focus.set_corner_radius_all(15)
			focus.draw(get_canvas_item(), track.grow(3))
		draw_string(copy_font, Vector2(55, size.y / 2 + 5), "Drumx drum sounds", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, PAPER)


class VolumeSlider:
	extends HSlider

	func _init() -> void:
		min_value = 0
		max_value = 1
		step = 0.01
		custom_minimum_size = Vector2(230, 36)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		accessibility_name = "Drum volume"
		accessibility_description = "Use Left and Right to adjust drum volume."
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color.TRANSPARENT, Color.TRANSPARENT])
		var invisible := GradientTexture2D.new()
		invisible.gradient = gradient
		invisible.width = 22
		invisible.height = 22
		for name in ["grabber", "grabber_highlight", "grabber_disabled"]:
			add_theme_icon_override(name, invisible)
		for name in ["slider", "grabber_area", "grabber_area_highlight", "focus"]:
			add_theme_stylebox_override(name, StyleBoxEmpty.new())
		value_changed.connect(func(_value):
			tooltip_text = "Drum volume: %d%%" % roundi(value * 100)
			queue_redraw())
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var y := size.y / 2
		var left := 11.0
		var right := maxf(left, size.x - 11)
		var x := lerpf(left, right, clampf((float(value) - min_value) / maxf(0.000001, max_value - min_value), 0, 1))
		draw_line(Vector2(left, y), Vector2(right, y), Color(PAPER, 0.13), 4, true)
		draw_line(Vector2(left, y), Vector2(x, y), LIME, 4, true)
		if has_focus():
			draw_arc(Vector2(x, y), 12, 0, TAU, 32, Color(LIME, 0.9), 1, true)
		elif editable and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
			draw_circle(Vector2(x, y), 12, Color(LIME, 0.14))
		draw_circle(Vector2(x, y), 8, PAPER)


class FoundationKit:
	extends "res://scripts/game_canvas.gd"
	const SETUP_PAD_COLORS = [Color(0.54, 0.792, 0.808), Color(0.807, 0.917, 0.578), Color(0.865, 0.683, 0.442)]
	var pad_buttons: Array[Button] = []
	var last_velocity := 0
	var last_pad := -1

	func _ready() -> void:
		super._ready()
		font = Menu.make_font(500)
		for index in range(3):
			var pad_button := Button.new()
			pad_button.focus_mode = Control.FOCUS_ALL
			pad_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			pad_button.accessibility_name = "Select %s mapping" % PAD_NAMES[index]
			pad_button.tooltip_text = "Select %s mapping" % PAD_NAMES[index]
			for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
				pad_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			pad_button.pressed.connect(func(): pad_selected.emit(index))
			pad_button.focus_entered.connect(queue_redraw)
			pad_button.focus_exited.connect(queue_redraw)
			pad_button.mouse_entered.connect(queue_redraw)
			pad_button.mouse_exited.connect(queue_redraw)
			add_child(pad_button)
			pad_buttons.append(pad_button)
		for index in range(pad_buttons.size()):
			pad_buttons[index].focus_neighbor_left = pad_buttons[index].get_path_to(pad_buttons[posmod(index - 1, 3)])
			pad_buttons[index].focus_neighbor_right = pad_buttons[index].get_path_to(pad_buttons[(index + 1) % 3])
		_layout_pads()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_layout_pads()

	func pad_rect(pad: int) -> Rect2:
		var span := minf(175, minf(size.x * 0.35, maxf(100, (size.y - 80) * 0.43)))
		match pad:
			0: return Rect2(size.x * 0.11, 49, span, span * 0.88)
			1: return Rect2(size.x * 0.53, 89, span, span)
			_: return Rect2(size.x * 0.33, size.y - span * 0.8 - 60, span * 0.8, span * 0.8)

	func _layout_pads() -> void:
		for index in range(pad_buttons.size()):
			pad_buttons[index].position = pad_rect(index).position
			pad_buttons[index].size = pad_rect(index).size
		queue_redraw()

	func _oval(rect: Rect2, color: Color, fill: bool, thickness: float = 1) -> void:
		var points := PackedVector2Array()
		for index in range(65):
			var angle := TAU * float(index) / 64
			points.append(rect.get_center() + Vector2(cos(angle), sin(angle)) * rect.size / 2)
		if fill:
			draw_colored_polygon(points, color)
		else:
			draw_polyline(points, color, thickness, true)

	func draw_kit() -> void:
		text("FOUNDATION KIT", Vector2(24, 30), 11, MUTED)
		if not pulses.is_empty():
			last_velocity = int(pulses.back().get("velocity", 0))
			last_pad = int(pulses.back().get("pad", -1))
		for pad in range(3):
			var frame := pad_rect(pad)
			var disc := Rect2(frame.position + Vector2(12, 10), frame.size - Vector2(24, 50))
			var color: Color = SETUP_PAD_COLORS[pad]
			var pulsing := false
			for hit in pulses:
				if int(hit.pad) == pad and current_host >= float(hit.host_time) and current_host - float(hit.host_time) < 0.22:
					pulsing = true
			if pulsing:
				_oval(disc.grow(8), Color(color, 0.14), true)
			_oval(disc, Color(color, 0.26 if pulsing else 0.11 if selected_pad == pad else 0.045), true)
			var focused := pad < pad_buttons.size() and pad_buttons[pad].has_focus()
			var hovered := pad < pad_buttons.size() and Rect2(Vector2.ZERO, pad_buttons[pad].size).has_point(pad_buttons[pad].get_local_mouse_position())
			_oval(disc, Color(color, 0.95 if focused or selected_pad == pad or pulsing or learn_pad == pad else 0.58 if hovered else 0.3), false, 2 if focused or selected_pad == pad else 1)
			if focused: _oval(disc.grow(5), Color(color, 0.48), false, 1)
			for fraction in [0.12, 0.22, 0.34] if pad == 0 else [0.07]:
				var inset := disc.size * float(fraction)
				_oval(Rect2(disc.position + inset, disc.size - inset * 2), Color(color, 0.18), false)
			if pad == 0:
				draw_circle(disc.get_center(), 4, Color(color, 0.6))
			elif pad == 2:
				var pedal := StyleBoxFlat.new()
				pedal.bg_color = Color(color, 0.17)
				pedal.set_corner_radius_all(6)
				pedal.draw(get_canvas_item(), Rect2(disc.get_center() - Vector2(10, 16), Vector2(20, 32)))
			draw_string(font, frame.position + Vector2(0, frame.size.y - 21), PAD_NAMES[pad].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 12, color)
			var receipt := "Strike to add a note" if learn_pad == pad else "MIDI received" if pad in checked else "Waiting for MIDI"
			draw_string(font, frame.position + Vector2(0, frame.size.y - 4), receipt, HORIZONTAL_ALIGNMENT_CENTER, frame.size.x, 11, LIME if learn_pad == pad or pad in checked else MUTED)
			if pad < pad_buttons.size():
				pad_buttons[pad].accessibility_description = receipt
		var track := Rect2(24, size.y - 14, maxf(1, size.x - 48), 3)
		draw_rect(track, Color(PAPER, 0.06))
		track.size.x *= float(last_velocity) / 127
		draw_rect(track, SETUP_PAD_COLORS[last_pad] if last_pad >= 0 and last_pad < 3 else MUTED)

	func _gui_input(_event: InputEvent) -> void:
		# The real pad buttons own pointer and keyboard hit areas, including focus.
		pass


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_heading = _label("Settings", 36, PAPER, 700)
	add_child(_heading)
	for index in range(4):
		var tab := _button(["Kit", "Sound", "Controls", "Progress"][index], func(): select_section(index))
		tab.accessibility_description = "Settings section"
		tab.gui_input.connect(func(event): _tab_input(event, index))
		_tabs.append(tab)
		add_child(tab)
	_status_label = _label("", 13, CORAL, 500, true)
	_status_label.visible = false
	add_child(_status_label)
	_body_scroll = ScrollContainer.new()
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_body_scroll.follow_focus = true
	add_child(_body_scroll)
	_body_content = Control.new()
	_body_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(_body_content)
	_build_kit()
	_build_sound()
	_build_playing()
	_build_progress()
	select_section(0)
	refresh_state()
	call_deferred("_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _heading != null:
		_layout()


func _draw() -> void:
	if _tabs.is_empty() or _body_scroll == null:
		return
	var y := _tabs[0].position.y + _tabs[0].size.y + 2
	draw_line(Vector2(_tabs[0].position.x, y), Vector2(_tabs[0].position.x + _body_scroll.size.x, y), Color(PAPER, 0.09), 1)
	var selected := _tabs[selected_section]
	draw_line(Vector2(selected.position.x + 14, y), Vector2(selected.position.x + selected.size.x - 14, y), LIME, 2)


func _font(weight: int = 400) -> Font:
	if not _fonts.has(weight):
		_fonts[weight] = Menu.make_font(weight)
	return _fonts[weight]


func _label(value: String, points: int, color: Color = PAPER, weight: int = 400, wrap: bool = false) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_override("font", _font(weight))
	item.add_theme_font_size_override("font_size", points)
	item.add_theme_color_override("font_color", color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item


func _surface() -> StyleBoxFlat:
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(1, 1, 1, 0.025)
	surface.border_color = Color(1, 1, 1, 0.065)
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(18)
	return surface


func _style_button(item: Button, primary: bool = false) -> void:
	item.add_theme_font_override("font", _font(600))
	item.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = LIME if primary else Color(PAPER, 0.025)
		if state == "hover":
			box.bg_color = Color("def3a5") if primary else Color(PAPER, 0.065)
		elif state == "pressed":
			box.bg_color = Color("b8d675") if primary else Color(PAPER, 0.1)
		elif state == "disabled":
			box.bg_color = Color(PAPER, 0.025)
		elif state == "focus":
			box.bg_color = Color.TRANSPARENT
		box.border_color = LIME if state == "focus" else Color(PAPER, 0.1)
		box.set_border_width_all(2 if state == "focus" else 1)
		box.set_corner_radius_all(10)
		box.content_margin_left = 18
		box.content_margin_right = 18
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		item.add_theme_stylebox_override(state, box)
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		item.add_theme_color_override(name, INK if primary else PAPER)
	item.add_theme_color_override("font_disabled_color", MUTED)


func _style_section(item: Button, selected: bool) -> void:
	item.add_theme_font_override("font", _font(600))
	item.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(PAPER, 0.04) if state == "hover" or state == "pressed" else Color.TRANSPARENT
		if state == "focus":
			box.border_color = Color(LIME, 0.8)
			box.set_border_width_all(1)
		box.set_corner_radius_all(4)
		item.add_theme_stylebox_override(state, box)
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		item.add_theme_color_override(name, PAPER if selected or name != "font_color" else MUTED)


func _button(value: String, action: Callable, primary: bool = false) -> Button:
	var item := Button.new()
	item.text = value
	item.custom_minimum_size.y = 44
	item.focus_mode = Control.FOCUS_ALL
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.pressed.connect(action)
	_style_button(item, primary)
	return item


func _build_kit() -> void:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _surface())
	_panels.append(panel)
	_body_content.add_child(panel)
	kit_canvas = FoundationKit.new()
	kit_canvas.kind = "kit"
	kit_canvas.pad_selected.connect(_select_pad)
	panel.add_child(kit_canvas)
	signal_label = _label("Strike a pad to see its signal.", 12, PAPER, 500, true)
	panel.add_child(signal_label)
	_kit_details = VBoxContainer.new()
	_kit_details.add_theme_constant_override("separation", 18)
	panel.add_child(_kit_details)
	_kit_details.add_child(_label("MIDI input", 24, PAPER, 600))
	source_option = OptionButton.new()
	source_option.custom_minimum_size.y = 44
	source_option.clip_text = true
	source_option.accessibility_name = "MIDI input"
	source_option.item_selected.connect(func(index):
		_call("select_source", [index])
		refresh_state())
	_style_button(source_option)
	_kit_details.add_child(source_option)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 7)
	_mapping_title = _label("Snare", 24, PAPER, 600)
	mapping_label = _label("MIDI notes  38 · 40", 13, MUTED, 500, true)
	names.add_child(_mapping_title)
	names.add_child(mapping_label)
	_kit_details.add_child(names)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_learn_button = _button("Add MIDI note", _begin_learning, true)
	actions.add_child(_learn_button)
	_cancel_button = _button("Cancel", _cancel_learning)
	actions.add_child(_cancel_button)
	_kit_details.add_child(actions)
	_mapping_help = _label("Choose your MIDI input, then strike each pad to check its signal.", 13, MUTED, 400, true)
	_mapping_help.custom_minimum_size.y = 36
	_kit_details.add_child(_mapping_help)
	_receipt_status = _label("Waiting for your kit", 13, LIME, 500)
	_kit_details.add_child(_receipt_status)
	_kit_details.add_child(_button("Open current lesson", _go_to_lesson))


func _setting_row(title: String, detail: String, accessory: Control, accessory_width: float = 230) -> Control:
	var item := SettingRow.new()
	var divider := StyleBoxFlat.new()
	divider.bg_color = Color.TRANSPARENT
	divider.border_color = Color(PAPER, 0.085)
	divider.border_width_bottom = 1
	item.add_theme_stylebox_override("panel", divider)
	item.custom_minimum_size.y = 96
	item.accessory = accessory
	item.accessory_width = accessory_width
	item.copy = VBoxContainer.new()
	item.copy.add_theme_constant_override("separation", 6)
	item.copy.add_child(_label(title, 17, PAPER, 500))
	item.copy.add_child(_label(detail, 14, MUTED, 400, true))
	item.add_child(item.copy)
	item.add_child(accessory)
	return item


func _content_panel(title: String, rows: Array, footnote: String) -> void:
	var panel := Control.new()
	_panels.append(panel)
	_body_content.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 20)
	panel.add_child(stack)
	stack.add_child(_label(title, 24, PAPER, 600))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	for item in rows:
		body.add_child(item)
	stack.add_child(body)
	stack.add_child(_label(footnote, 14, MUTED, 400, true))
	_centered_stacks.append({"panel": panel, "stack": stack})


func _build_sound() -> void:
	_monitor_toggle = SoundToggle.new()
	_monitor_toggle.copy_font = _font(500)
	_monitor_toggle.toggled.connect(_set_monitoring)
	_volume_slider = VolumeSlider.new()
	_volume_slider.custom_minimum_size.x = 172
	_volume_slider.value_changed.connect(_set_volume)
	var volume_control := HBoxContainer.new()
	volume_control.add_theme_constant_override("separation", 10)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_control.add_child(_volume_slider)
	_volume_readout = _label("100%", 13, PAPER, 500)
	_volume_readout.custom_minimum_size.x = 48
	_volume_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_volume_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_control.add_child(_volume_readout)
	_audio_status = _label("", 12, MUTED, 400, true)
	_content_panel("Audio", [
		_setting_row("Drum sounds", "Turn off when listening to your module's own sounds.", _monitor_toggle),
		_setting_row("Volume", "Keep the click and your drums comfortable to hear together.", volume_control),
		_setting_row("Audio connection", "Reopen the system's current output after changing your listening route.", _button("Retry audio", _retry_audio, true), 150),
		_audio_status,
	], "Audio uses this computer's selected output. USB MIDI sends notes, not your module's audio.")


func _build_playing() -> void:
	_content_panel("Playing controls", [
		_setting_row("Practice setup", "Choose the tempo, phrase length, and visual guidance in your lesson.", _button("Open lesson", _go_to_lesson, true), 180),
		_setting_row("Hand suggestions", "R / L suggest which hand to use. MIDI cannot verify your hands.", _label("R / L", 18, LIME, 600), 90),
		_setting_row("Kit navigation and timing", "Drum-menu navigation and scoring offset are not available in this preview.", _label("UNAVAILABLE", 11, MUTED, 600), 130),
	], "A MIDI timing result does not assess grip, rebound, posture, or technique.")


func _build_progress() -> void:
	_saved_takes = _label("0 TAKES", 15, LIME, 600)
	_saved_lesson = _label("Find the pulse", 15, PAPER, 500, true)
	_retry_save_button = _button("Retry save", func(): _call("retry_progress_save"), true)
	_content_panel("Saved progress", [
		_setting_row("Practice history", "Completed takes and reading answers save on this computer.", _saved_takes, 150),
		_setting_row("Save recovery", "If saving is interrupted, keep Drumx open and retry. An unreadable original file stays preserved.", _retry_save_button, 150),
		_setting_row("Selected lesson", "Continue on the main menu opens this step.", _saved_lesson, 270),
		_setting_row("Local practice record", "Separate players and imports from the Mac lab are not available in this preview.", _label("LOCAL SAVE", 11, MUTED, 600), 130),
	], "This preview uses its own save file. It does not replace the native Mac app's progress.")


func _layout() -> void:
	if _heading == null or _panels.size() != 4:
		return
	var width := minf(1120, maxf(1, size.x - 88))
	var x := (size.x - width) / 2
	var top := minf(44, maxf(24, size.y * 0.045))
	_heading.position = Vector2(x, top)
	_heading.size = Vector2(width, 48)
	var tab_y := top + 62
	var tab_height := 48.0
	var tab_width := minf(136, (width - 48) / 4)
	for index in range(4):
		_tabs[index].position = Vector2(x + float(index) * (tab_width + 16), tab_y)
		_tabs[index].size = Vector2(tab_width, tab_height)
	_status_label.position = Vector2(x, tab_y + tab_height + 10)
	_status_label.size.x = width
	var status_height := maxf(20, _status_label.get_combined_minimum_size().y) if _status_label.visible else 0.0
	_status_label.size.y = status_height
	var status_space := status_height + 10 if _status_label.visible else 0.0
	var body_y := tab_y + tab_height + 32 + status_space
	var body_height := maxf(1, size.y - body_y - 28)
	_body_scroll.position = Vector2(x, body_y)
	_body_scroll.size = Vector2(width, body_height)
	_kit_details.size.x = width * 0.5 - 44
	var required_height := maxf(430, _kit_details.get_combined_minimum_size().y + 40)
	if selected_section > 0:
		var selected_stack: VBoxContainer = _centered_stacks[selected_section - 1].stack
		selected_stack.size.x = width
		required_height = selected_stack.get_combined_minimum_size().y + 12
	var content_width := width
	if required_height > body_height:
		content_width -= _body_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var panel_rect := Rect2(Vector2.ZERO, Vector2(content_width, maxf(required_height, body_height)))
	_body_content.custom_minimum_size.y = panel_rect.size.y
	_body_content.size = panel_rect.size
	for panel in _panels:
		panel.position = panel_rect.position
		panel.size = panel_rect.size
	kit_canvas.position = Vector2(16, 16)
	kit_canvas.size = Vector2(content_width * 0.5 - 32, panel_rect.size.y - 32)
	signal_label.position = kit_canvas.position + Vector2(24, kit_canvas.size.y - 40)
	signal_label.size = Vector2(kit_canvas.size.x - 48, 22)
	_kit_details.size.x = content_width * 0.5 - 44
	_kit_details.size.y = _kit_details.get_combined_minimum_size().y
	_kit_details.position = Vector2(content_width * 0.5 + 16, maxf(16, (panel_rect.size.y - _kit_details.size.y) / 2))
	for entry in _centered_stacks:
		var stack: VBoxContainer = entry.stack
		stack.size.x = content_width
		stack.size.y = stack.get_combined_minimum_size().y
		stack.position = Vector2(0, 4)
	queue_redraw()


func _tab_input(event: InputEvent, index: int) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var target := index
	match event.keycode:
		KEY_LEFT: target = posmod(index - 1, _tabs.size())
		KEY_RIGHT: target = (index + 1) % _tabs.size()
		KEY_HOME: target = 0
		KEY_END: target = _tabs.size() - 1
		_: return
	select_section(target)
	_tabs[target].grab_focus()
	_tabs[index].accept_event()


func select_section(index: int) -> void:
	if selected_section == 0 and index != 0:
		_cancel_learning()
	selected_section = clampi(index, 0, 3)
	_body_scroll.scroll_vertical = 0
	for item in range(_panels.size()):
		_panels[item].visible = item == selected_section
		_style_section(_tabs[item], item == selected_section)
		_tabs[item].accessibility_description = "Selected settings section" if item == selected_section else "Settings section"
	call_deferred("_layout")


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.1:
		_refresh_elapsed = 0
		refresh_state()


func refresh_state() -> void:
	if controller == null or _mapping_title == null:
		return
	var pad := clampi(int(controller.get("selected_pad")), 0, 2)
	var state: Dictionary = controller.get("snapshot")
	var groups: Array = controller.get("mappings")
	var received: Array = controller.get("checked")
	var source := str(controller.get("source_id"))
	var pending := int(state.get("pending_pad", -1))
	var disconnected := bool(state.get("source_lost", false))
	_mapping_title.text = PAD_NAMES[pad]
	if groups.size() == 3:
		var notes: Array = groups[pad]
		mapping_label.text = "No MIDI notes assigned" if notes.is_empty() else "MIDI notes  " + " · ".join(notes.map(func(note): return str(note)))
	_cancel_button.visible = pending >= 0
	_learn_button.disabled = source.is_empty() or disconnected or pending >= 0
	_learn_button.text = "Waiting for a strike" if pending >= 0 else "Add MIDI note"
	_learn_button.tooltip_text = "Choose your MIDI input first." if source.is_empty() or disconnected else "Learning is active. Strike the selected pad or choose Cancel." if pending >= 0 else "Add an alias while keeping this pad's existing MIDI notes."
	_mapping_help.text = "Your input disconnected. Choose it again, or explicitly choose Keyboard preview." if disconnected else "Strike the selected pad once. Existing notes stay assigned." if pending >= 0 else "Choose your module in the input menu above. Keyboard preview cannot verify your MIDI kit." if source.is_empty() else "Select a pad on the left. Add a MIDI note only if its mapping needs a change."
	_receipt_status.text = "MIDI disconnected · choose an input" if disconnected else "%d / 3 pads received" % received.size() if source != "" else "Keyboard preview · choose MIDI to check your kit"
	_receipt_status.add_theme_color_override("font_color", LIME if source != "" and not disconnected and received.size() == 3 else MUTED)
	kit_canvas.selected_pad = pad
	kit_canvas.checked = received if source != "" and not disconnected else []
	kit_canvas.learn_pad = pending
	_monitor_toggle.set_pressed_no_signal(bool(controller.get("monitoring")))
	_monitor_toggle.queue_redraw()
	_volume_slider.set_value_no_signal(float(controller.get("volume")))
	_volume_readout.text = "%d%%" % roundi(_volume_slider.value * 100)
	_volume_slider.tooltip_text = "Drum volume: " + _volume_readout.text
	_volume_slider.queue_redraw()
	_audio_status.text = "Audio output connected. Check your listening volume before playing." if bool(state.get("audio_ready", false)) else "Audio output is not connected. Choose Retry audio to try the current system output."
	_audio_status.add_theme_color_override("font_color", MUTED if bool(state.get("audio_ready", false)) else CORAL)
	var status_error := str(state.get("error", ""))
	var model: Object = controller.get("model")
	if model != null:
		var saved: Dictionary = model.get("save")
		var attempts: Array = saved.get("attempts", [])
		_saved_takes.text = "%d TAKE%s" % [attempts.size(), "" if attempts.size() == 1 else "S"]
		if bool(model.get("blocked")): _saved_takes.text = "FILE PRESERVED"
		if str(model.get("error")) != "": status_error = str(model.get("error"))
		var pending_saves := int(model.pending_save_count()) if model.has_method("pending_save_count") else 0
		if pending_saves > 0: status_error = str(model.pending_save_message())
		_retry_save_button.disabled = pending_saves == 0 and not bool(model.get("blocked")) and str(model.get("error")).is_empty()
		_retry_save_button.tooltip_text = status_error if not _retry_save_button.disabled else "Your practice is saved on this computer."
		var course: Dictionary = model.get("course")
		var lessons: Array = course.get("lessons", [])
		if not lessons.is_empty():
			_saved_lesson.text = str(lessons[clampi(int(saved.get("selected", 0)), 0, lessons.size() - 1)].title)
		if bool(model.get("blocked")): _saved_lesson.text = "Saved lesson unavailable"
	_status_label.text = status_error
	_status_label.visible = not status_error.is_empty()
	_status_label.accessibility_name = status_error
	call_deferred("_layout")


func _call(method: String, arguments: Array = []) -> void:
	if controller != null and controller.has_method(method):
		controller.callv(method, arguments)


func _select_pad(pad: int) -> void:
	if controller == null:
		return
	_call("select_kit_pad" if controller.has_method("select_kit_pad") else "select_pad", [pad])
	refresh_state()


func _begin_learning() -> void:
	if _learn_button.disabled: return
	_call("begin_learning")
	refresh_state()


func _cancel_learning() -> void:
	if controller == null:
		return
	if controller.has_method("cancel_learning"):
		_call("cancel_learning")
	else:
		var engine: Object = controller.get("engine")
		if engine != null:
			engine.cancel_learning()
		_call("refresh_mapping")
	refresh_state()


func _go_to_lesson() -> void:
	if controller != null:
		_call("show_prepare", [int(controller.get("lesson_index"))])


func _set_monitoring(enabled: bool) -> void:
	if controller == null:
		return
	controller.set("monitoring", enabled)
	var engine: Object = controller.get("engine")
	if engine != null:
		engine.set_monitoring(enabled)
	_call("save_settings")


func _set_volume(value: float) -> void:
	if controller == null:
		return
	controller.set("volume", value)
	_volume_readout.text = "%d%%" % roundi(value * 100)
	var engine: Object = controller.get("engine")
	if engine != null:
		engine.set_volume(value)
	_call("save_settings")


func _retry_audio() -> void:
	if controller == null:
		return
	var engine: Object = controller.get("engine")
	if engine != null:
		engine.load_sample_bank("res://assets/BigRusty")
		controller.set("snapshot", engine.snapshot())
	_call("update_footer")
	refresh_state()
