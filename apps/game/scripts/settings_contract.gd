extends RefCounted

const Settings = preload("res://scripts/settings_panel.gd")
const Menu = preload("res://scripts/main_menu.gd")
const LearningPath = preload("res://scripts/learning_path.gd")
const DataModel = preload("res://scripts/game_data.gd")

class FixtureController extends RefCounted:
	var selected_pad := 1
	var snapshot := {"pending_pad": -1, "audio_ready": true, "error": ""}
	var mappings: Array = [[42, 44, 46], [38, 40], [35, 36]]
	var checked: Array = [0, 1, 2]
	var source_id := ""
	var monitoring := true
	var volume := 0.7
	var model: Object
	var engine: Object
	var lesson_index := 0
	var learning_calls := 0
	var cancel_calls := 0
	var save_calls := 0
	func begin_learning() -> void:
		learning_calls += 1
		snapshot.pending_pad = selected_pad
	func cancel_learning() -> void:
		cancel_calls += 1
		snapshot.pending_pad = -1
	func select_pad(pad: int) -> void:
		selected_pad = pad
		snapshot.pending_pad = -1
	func save_settings() -> void: save_calls += 1
	func show_prepare(index: int) -> void: lesson_index = index

# Offscreen view fixtures exercise layout and interactions without opening a
# window, changing a player's settings, or creating native device connections.
static func run_checks(host: Node) -> Dictionary:
	var result := {"checks": 0, "failures": []}
	var check := func(ok: bool, label: String) -> void:
		result.checks += 1
		if not ok: result.failures.append(label)
	var tree := host.get_tree()
	if tree == null:
		check.call(false, "Settings contracts require an existing scene tree")
		return result
	var harness := Control.new()
	harness.position = Vector2(-10000, -10000)
	harness.size = Vector2(1080, 640)
	tree.root.add_child(harness)
	var controller := FixtureController.new()
	controller.model = DataModel.new()
	check.call(controller.model.load_course(), "Authored course loads without player history")
	var panel := Settings.new()
	panel.controller = controller
	harness.add_child(panel)
	await tree.process_frame
	await tree.process_frame
	panel.refresh_state()
	check.call(panel._learn_button.disabled, "Keyboard preview cannot arm MIDI learning")
	panel._begin_learning()
	check.call(controller.learning_calls == 0 and panel.kit_canvas.checked.is_empty(), "Keyboard state never becomes MIDI verification")
	check.call(panel._receipt_status.text.contains("Keyboard preview"), "Input readiness names the keyboard preview accurately")
	check.call(panel._volume_readout.text == "70%", "Volume has a readable current value")
	controller.source_id = "fixture-midi"
	controller.checked = [1]
	panel.refresh_state()
	check.call(not panel._learn_button.disabled and panel._receipt_status.text == "1 / 3 pads received", "Selected MIDI input exposes learning and precise pad receipt count")
	panel._begin_learning()
	check.call(controller.learning_calls == 1 and panel._learn_button.disabled and panel._cancel_button.visible, "Learning shows a waiting state and a real Cancel action")
	panel._begin_learning()
	check.call(controller.learning_calls == 1, "Waiting state does not rearm learning on repeated activation")
	panel.select_section(1)
	check.call(controller.cancel_calls == 1 and int(controller.snapshot.pending_pad) == -1, "Leaving kit settings cancels its pending learn action")
	check.call(panel._panels.filter(func(item): return item.visible).size() == 1 and panel._panels[1].visible, "Only the selected settings body is exposed")
	var right := InputEventKey.new()
	right.pressed = true
	right.keycode = KEY_RIGHT
	panel._tab_input(right, 1)
	check.call(panel.selected_section == 2 and panel._tabs[2].has_focus(), "Right Arrow selects and focuses the next section")
	var home := InputEventKey.new()
	home.pressed = true
	home.keycode = KEY_HOME
	panel._tab_input(home, 2)
	check.call(panel.selected_section == 0 and panel._tabs[0].has_focus(), "Home returns to the first section")
	panel._select_pad(2)
	check.call(controller.selected_pad == 2 and panel._mapping_title.text == "Kick", "Selecting a kit pad updates its actual mapping controls")
	panel._set_volume(0.42)
	check.call(is_equal_approx(controller.volume, 0.42) and panel._volume_readout.text == "42%" and controller.save_calls == 1, "Volume changes update feedback and persistence once")
	controller.snapshot.error = "The MIDI source is no longer available."
	panel.refresh_state()
	check.call(panel._status_label.visible and panel._status_label.text == controller.snapshot.error, "Connection error is visible above every settings section")
	check.call(panel._audio_status.text.begins_with("Audio output connected"), "MIDI errors do not impersonate an audio disconnection")
	controller.model.blocked = true
	controller.model.error = "Saved progress could not be read. Your file has been preserved."
	panel.refresh_state()
	check.call(panel._saved_takes.text == "FILE PRESERVED" and panel._status_label.text == controller.model.error, "Unreadable progress does not display a misleading zero-take record")
	check.call(panel._saved_lesson.text == "Saved lesson unavailable", "Unreadable progress does not invent the prior selected lesson")
	check.call(not panel._retry_save_button.disabled, "Preserved unreadable progress exposes an explicit Retry save")
	controller.model.pending_attempts = {"waiting": {}}
	panel.refresh_state()
	check.call(panel._status_label.text == controller.model.pending_save_message(), "Waiting completed results stay visible even when another error exists")
	controller.model.pending_attempts.clear()
	controller.model.blocked = false
	controller.model.error = ""
	controller.snapshot.error = ""
	panel.refresh_state()
	for viewport in [Vector2(980, 540), Vector2(1080, 640), Vector2(1840, 1180)]:
		harness.size = viewport
		panel.size = viewport
		for section in range(4):
			panel.select_section(section)
			await tree.process_frame
			await tree.process_frame
			panel._layout()
			await tree.process_frame
			var scroll: ScrollContainer = panel._body_scroll
			check.call(scroll.position.y >= panel._tabs[0].position.y + panel._tabs[0].size.y and scroll.position.y + scroll.size.y <= viewport.y + 0.5, "Section %d body stays within %s" % [section, viewport])
			if section == 0:
				check.call(panel._kit_details.position.y + panel._kit_details.size.y <= panel._body_content.size.y + 0.5, "Kit actions remain reachable at %s" % viewport)
			else:
				var stack: VBoxContainer = panel._centered_stacks[section - 1].stack
				check.call(stack.position.y >= 0 and stack.position.y + stack.size.y <= panel._body_content.size.y + 0.5, "Section %d copy and controls fit its scrollable content at %s" % [section, viewport])
			if viewport.y >= 1180:
				check.call(not scroll.get_v_scroll_bar().visible, "Section %d avoids scrolling when everything fits" % section)
			elif viewport.y == 540 and section == 1:
				check.call(scroll.get_v_scroll_bar().visible, "Short Sound settings scroll instead of cropping controls")
	panel.queue_free()
	await tree.process_frame
	var menu := Menu.new()
	harness.add_child(menu)
	menu.size = Vector2(980, 540)
	await tree.process_frame
	menu.layout_menu()
	var activations := {"count": 0}
	menu.learn_requested.connect(func(): activations.count += 1)
	menu.actions[1].disabled = true
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	menu.actions[1]._gui_input(enter)
	menu.activate(1)
	check.call(activations.count == 0, "Disabled menu actions reject keyboard and direct activation")
	for action in menu.actions:
		check.call(action.get_combined_minimum_size().x <= action.size.x and action.get_combined_minimum_size().y <= action.size.y, "Hidden native text does not enlarge a custom menu hit rectangle")
	menu.queue_free()
	await tree.process_frame
	var path := LearningPath.new()
	path.configure(controller.model, 0)
	harness.add_child(path)
	path.size = Vector2(980, 540)
	await tree.process_frame
	path._layout()
	var plays := {"count": 0}
	path.play_requested.connect(func(_index): plays.count += 1)
	path._inspect(1)
	path._play._gui_input(enter)
	path._play_featured()
	check.call(path._play.disabled and plays.count == 0, "Inspecting a locked lesson never starts it through Enter")
	check.call(path._nodes[1].focus_mode == Control.FOCUS_ALL and not path._nodes[1].disabled, "Locked steps remain keyboard-inspectable")
	path._inspect(0)
	check.call(not path._play.focus_neighbor_bottom.is_empty() and not path._nodes[0].focus_neighbor_top.is_empty(), "Course action and path have explicit vertical focus routes")
	path._turn_page(1)
	check.call(path.chapter_page == 1 and path.featured_index == 12, "Next chapters reveal the first later lesson")
	check.call(path._nodes.filter(func(node): return node.visible).size() == 8, "Second page keeps eight later steps instead of squeezing twenty into a row")
	check.call(path._next_page.disabled and not path._previous_page.disabled and plays.count == 0, "Paging only inspects, with explicit final boundary")
	path._focus_step(11)
	check.call(path.chapter_page == 0 and path._nodes[11].has_focus(), "Keyboard navigation reveals and focuses the preceding chapter page")
	path._inspect(controller.model.course.lessons.size() - 1)
	check.call(path.chapter_page == 1 and path._nodes[19].visible, "Resuming or inspecting the last lesson opens its page")
	for viewport in [Vector2(980, 540), Vector2(1440, 780), Vector2(1840, 1180)]:
		path.size = viewport
		path._layout()
		for node in path._nodes:
			if node.visible:
				check.call(node.size.x >= 44 and node.size.y >= 44, "Expanded course nodes retain useful pointer targets")
				check.call(Rect2(Vector2.ZERO, path.size).encloses(Rect2(path.composition.position + node.position, node.size)), "Visible course steps stay within the viewport")
	for item in path._labels:
		check.call(item.view.get_theme_font_size("font_size") >= 11, "Learning path metadata remains readable at minimum size")
	harness.queue_free()
	await tree.process_frame
	return result
