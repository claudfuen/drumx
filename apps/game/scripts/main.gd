extends Control

const DataModel = preload("res://scripts/game_data.gd")
const Canvas = preload("res://scripts/game_canvas.gd")
const LearningPath = preload("res://scripts/learning_path.gd")
const MainMenu = preload("res://scripts/main_menu.gd")
const NotationContract = preload("res://scripts/notation_contract.gd")
const VisualContract = preload("res://scripts/visual_contract.gd")
const PracticeStage = preload("res://scripts/practice_stage.gd")
const ScoreReview = preload("res://scripts/score_review.gd")
const ScoreHUD = preload("res://scripts/score_hud.gd")
const SettingsPanel = preload("res://scripts/settings_panel.gd")
const INK = Color("0c1012")
const PAPER = Color("f0f2e8")
const MUTED = Color("92a5a3")
const LIME = Color("cbe880")
const PAD_NAMES = ["Hi-hat", "Snare", "Kick"]
var model = DataModel.new()
var engine: Object
var page := "main"
var lesson_index := 0
var tempo := 60.0
var bars := 16
var guidance := 0
var volume := 0.7
var monitoring := true
var source_id := ""
var mappings: Array = [[42, 44, 46], [38, 40], [35, 36]]
var snapshot: Dictionary = {}
var root_stack: VBoxContainer
var content: VBoxContainer
var footer: Label
var page_label: Label
var back: Button
var settings_button: Button
var stop_button: Button
var score_hud: Control
var canvas: Control
var hud: Label
var stage_feedback: Label
var mapping_label: Label
var kit_signal: Label
var settings_panel: Control
var source_option: OptionButton
var source_ids: Array = []
var selected_pad := 1
var checked: Array = []
var pulses: Array = []
var recent_offsets: Array = [[], [], []]
var take_id := ""
var take_settings: Dictionary = {}
var result_score: Label
var result_visual: Control
var next_lesson_button: Button
var result_grade_fingerprint := ""
var save_retry_at := 0.0
var result_metrics: Array[Label] = []
var check_return := "prepare"
var check_overlay: Control
var modal_focus: Array = []
var options_open := false
var result_detail: Label
var result_best: Label
var score_before := -1
var result_fingerprint := ""
var stage_done := false
var smoke := false
var preserve_error := ""
var sources_refresh_at := 0.0
var take_lesson_index := 0
var saved_fingerprint := ""

func _ready() -> void:
	smoke = "--smoke-test" in OS.get_cmdline_user_args() or "--ui-smoke-test" in OS.get_cmdline_user_args()
	if not model.load_course():
		push_error("The authored course could not be loaded.")
		get_tree().quit(1)
		return
	if ClassDB.class_exists("DrumxEngine"):
		engine = ClassDB.instantiate("DrumxEngine")
	if smoke:
		get_window().size = Vector2i(1140, 830)
		call_deferred("smoke_test")
		return
	configure_logical_window()
	if engine != null and OS.get_name() == "macOS":
		engine.configure_window(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id()))
	model.load_progress()
	lesson_index = clampi(int(model.save.selected), 0, 11)
	tempo = float(model.course.lessons[lesson_index].bpm)
	var saved: Dictionary = model.save.get("settings", {})
	volume = clampf(float(saved.get("volume", 0.7)), 0, 1)
	monitoring = bool(saved.get("monitoring", true))
	if saved.get("mapping") is Array:
		mappings = model.normalized_mapping(saved.mapping)
	setup_theme()
	build_shell()
	if engine != null:
		engine.set_mapping(mappings)
		mappings = engine.get_mapping()
		engine.set_volume(volume)
		engine.set_monitoring(monitoring)
		engine.load_sample_bank("res://assets/BigRusty")
		snapshot = engine.snapshot()
	else:
		preserve_error = "Native engine unavailable. This build cannot play yet."
	show_main()

func setup_theme() -> void:
	var look := Theme.new()
	look.default_font_size = 17
	look.default_font = MainMenu.make_font(400)
	look.set_color("font_color", "Label", PAPER)
	look.set_color("font_color", "Button", PAPER)
	look.set_color("font_hover_color", "Button", PAPER)
	look.set_color("font_focus_color", "Button", PAPER)
	look.set_color("font_disabled_color", "Button", Color(MUTED, 0.5))
	for control in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(PAPER, 0.025 if state == "normal" else 0.075)
			box.border_color = LIME if state == "focus" else Color(PAPER, 0.11)
			box.set_border_width_all(2 if state == "focus" else 1)
			box.set_corner_radius_all(9)
			box.content_margin_left = 22
			box.content_margin_right = 22
			box.content_margin_top = 14
			box.content_margin_bottom = 14
			look.set_stylebox(state, control, box)
	look.set_color("font_color", "OptionButton", PAPER)
	theme = look

func build_shell() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	root_stack = VBoxContainer.new()
	root_stack.add_theme_constant_override("separation", 18)
	margin.add_child(root_stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 12)
	header_margin.add_theme_constant_override("margin_right", 12)
	root_stack.add_child(header_margin)
	header_margin.add_child(header)
	var logo := label("drumx", 28, PAPER)
	logo.add_theme_font_override("font", MainMenu.make_font(700))
	header.add_child(logo)
	page_label = label("ENGINE PREVIEW", 11, MUTED)
	header.add_child(page_label)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(fill)
	score_hud = ScoreHUD.new()
	score_hud.visible = false
	header.add_child(score_hud)
	back = button("Main menu", show_main)
	header.add_child(back)
	settings_button = button("Settings", show_settings)
	header.add_child(settings_button)
	for navigation in [back, settings_button]:
		navigation.custom_minimum_size.y = 43
		navigation.add_theme_font_size_override("font_size", 14)
		navigation.add_theme_font_override("font", MainMenu.make_font(600))
		for state in ["normal", "hover", "pressed"]:
			var empty := StyleBoxEmpty.new()
			empty.content_margin_left = 18
			empty.content_margin_right = 18
			navigation.add_theme_stylebox_override(state, empty)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	root_stack.add_child(content)
	footer = label("", 11, MUTED)
	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", 12)
	footer_margin.add_theme_constant_override("margin_right", 12)
	root_stack.add_child(footer_margin)
	var footer_row := row()
	footer_margin.add_child(footer_row)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_row.add_child(footer)
	stop_button = button("Stop", stop_take)
	stop_button.custom_minimum_size.y = 43
	stop_button.visible = false
	footer_row.add_child(stop_button)

func label(value: String, font_size: int = 17, color: Color = PAPER, wrap: bool = false) -> Label:
	var item := Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.add_theme_font_override("font", MainMenu.make_font(600 if font_size >= 22 else 400))
	if wrap:
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

func button(value: String, action: Callable, primary: bool = false) -> Button:
	var item := Button.new()
	item.text = value
	item.custom_minimum_size.y = 48
	item.pressed.connect(action)
	if primary:
		for state in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = LIME if state == "normal" else Color("def5a2")
			box.set_corner_radius_all(9)
			box.content_margin_left = 28
			box.content_margin_right = 28
			box.content_margin_top = 18
			box.content_margin_bottom = 18
			item.add_theme_stylebox_override(state, box)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			item.add_theme_color_override(color_name, INK)
	return item

func row() -> HBoxContainer:
	var item := HBoxContainer.new()
	item.add_theme_constant_override("separation", 16)
	return item

func gap(parent: Container, minimum: float = 0, expand: bool = false) -> void:
	var item := Control.new()
	item.custom_minimum_size.y = minimum
	if expand:
		item.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(item)

func clear_page(destination: String) -> void:
	if engine != null and page == "stage" and destination != "result":
		engine.stop()
	if engine != null and page == "settings":
		engine.cancel_learning()
	page = destination
	content.add_theme_constant_override("separation", 14 if destination == "settings" else 20)
	canvas = null
	settings_panel = null
	source_option = null
	hud = null
	stage_feedback = null
	mapping_label = null
	kit_signal = null
	result_score = null
	result_visual = null
	next_lesson_button = null
	result_metrics.clear()
	result_detail = null
	result_best = null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	back.visible = destination not in ["main", "stage"]
	settings_button.visible = destination not in ["main", "stage", "settings"]
	score_hud.visible = destination == "stage"
	stop_button.visible = destination == "stage"
	page_label.text = {"main": "MAIN MENU", "learn": "FOUNDATIONS", "prepare": "LESSON", "stage": "PRACTICE", "result": "REVIEW", "pause": "PAUSED", "settings": "SETTINGS"}.get(destination, destination.to_upper())
	update_footer()

func update_footer() -> void:
	if footer == null:
		return
	var message: String = preserve_error if preserve_error != "" else str(model.error)
	if message == "" and engine != null:
		message = str(snapshot.get("error", ""))
	if message == "" and page == "main":
		footer.text = "↑ ↓  choose    RETURN  select"
		return
	footer.text = message if message != "" else "A  hi-hat   ·   S  snare   ·   SPACE  kick   ·   SHIFT  softer   /   ESC  pause" if page == "stage" else "A  hi-hat   ·   S  snare   ·   SPACE  kick   /   ESC  main menu"

func show_main() -> void:
	clear_page("main")
	var menu := MainMenu.new()
	menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lesson: Dictionary = model.course.lessons[lesson_index]
	menu.configure({"lesson": lesson.title, "chapter": model.course.chapters[int(lesson.chapter)],
		"chapter_index": int(lesson.chapter), "player": "Player 1", "unlocked": model.frontier() + 1,
		"cleared": cleared_count(), "total": 12})
	menu.continued.connect(func(): show_prepare(lesson_index))
	menu.learn_requested.connect(func(): show_learn(model.frontier()))
	menu.settings_requested.connect(show_settings)
	content.add_child(menu)
	if not smoke: menu.call_deferred("focus_primary")

func configure_logical_window() -> void:
	# Godot window sizes are physical pixels. AppKit authored geometry uses
	# logical points. Apply OS density once, then keep all layout in logical units.
	var density := 1.0
	if OS.get_name() == "macOS":
		density = DisplayServer.screen_get_max_scale()
	elif OS.get_name() == "Windows":
		density = clampf(float(DisplayServer.screen_get_dpi()) / 96.0, 1.0, 3.0)
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_factor = density
	var usable := DisplayServer.screen_get_usable_rect()
	var desired := Vector2i(Vector2(1140, 830) * density)
	var minimum := Vector2i(Vector2(1020, 780) * density)
	# Respect a smaller desktop while keeping the authored size on normal screens.
	var maximum := Vector2i(usable.size.x - 48 * density, usable.size.y - 48 * density)
	window.min_size = minimum.min(maximum)
	window.size = desired.min(maximum)
	window.position = usable.position + (usable.size - window.size) / 2

func cleared_count() -> int:
	var count := 0
	for index in range(12):
		if model.cleared(index):
			count += 1
	return count

func star_string(value: int) -> String:
	return "★".repeat(value) + "☆".repeat(5 - value)

func show_learn(index: int) -> void:
	clear_page("learn")
	var path := LearningPath.new()
	path.configure(model, index)
	path.play_requested.connect(show_prepare)
	content.add_child(path)

func show_prepare(index: int) -> void:
	var changed := lesson_index != index
	lesson_index = index
	model.save.selected = index
	if not smoke: model.persist()
	if changed:
		tempo = float(model.course.lessons[index].bpm)
		bars = 16
		guidance = 0
	build_prepare()

func centered_column(spacing: int = 16) -> VBoxContainer:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 880
	stack.add_theme_constant_override("separation", spacing)
	center.add_child(stack)
	return stack

func build_prepare() -> void:
	clear_page("prepare")
	var lesson: Dictionary = model.course.lessons[lesson_index]
	var stack := centered_column()
	stack.add_child(label("HEAR IT. COUNT IT. MAKE IT YOURS.", 11, LIME))
	stack.add_child(label(lesson.title, 42, PAPER, true))
	stack.add_child(label(lesson.objective, 18, Color(PAPER, 0.8), true))
	stack.add_child(label(lesson.explanation, 14, MUTED, true))
	canvas = load("res://scripts/drum_notation.gd").new()
	canvas.authored = lesson.events
	canvas.lesson_title = lesson.title
	stack.add_child(canvas)
	stack.add_child(label("Count " + str(lesson.counts) + "  ·  R and L are suggested sticking, not verified hands.", 12, MUTED, true))
	stage_feedback = label("", 13, MUTED)
	stack.add_child(stage_feedback)
	update_prepare_summary()
	var controls := row()
	controls.visible = options_open
	stack.add_child(controls)
	controls.add_child(label("TEMPO", 10, MUTED))
	var speed = SettingsPanel.VolumeSlider.new()
	speed.min_value = 30
	speed.max_value = 240
	speed.step = 1
	speed.value = tempo
	speed.custom_minimum_size.x = 115
	speed.accessibility_name = "Practice tempo"
	speed.accessibility_description = "Use Left and Right to adjust beats per minute."
	speed.tooltip_text = "%d BPM" % tempo
	controls.add_child(speed)
	var tempo_label := label("%d BPM" % tempo, 13, PAPER)
	tempo_label.custom_minimum_size.x = 70
	controls.add_child(tempo_label)
	speed.value_changed.connect(func(value): tempo = value; tempo_label.text = "%d BPM" % tempo; speed.tooltip_text = tempo_label.text; update_prepare_summary())
	var length := OptionButton.new()
	for caption in ["1 bar · repair", "4 bars · short", "8 bars", "16 bars · practice", "32 bars"]:
		length.add_item(caption)
	length.select([1, 4, 8, 16, 32].find(bars))

	controls.add_child(length)
	var mode := OptionButton.new()
	for caption in ["Follow the track", "Hide alternate bars", "Click-only recall"]: mode.add_item(caption)
	mode.select(guidance)
	mode.item_selected.connect(func(choice):
		guidance = choice
		if guidance == 1 and bars == 1: bars = 4; length.select(1)
		update_prepare_summary())
	length.item_selected.connect(func(choice):
		bars = [1, 4, 8, 16, 32][choice]
		if bars == 1 and guidance == 1: guidance = 0; mode.select(0)
		update_prepare_summary())
	controls.add_child(mode)
	var actions := row()
	stack.add_child(actions)
	var start := button("Start playing", start_take, true)
	start.disabled = engine == null
	actions.add_child(start)
	actions.add_child(button("Lesson check", show_learning_check))
	var options := button("Practice options", func(): options_open = not options_open; controls.visible = options_open)
	actions.add_child(options)
	stack.add_child(label("Reading check saved." if model.save.read.get(lesson.version, false) else "Read the bar, then keep counting as you play.", 12, LIME))
	if not smoke: start.call_deferred("grab_focus")

func update_prepare_summary() -> void:
	if stage_feedback != null:
		stage_feedback.text = "%d BPM · %d bars · About %d seconds of playing · Four-beat count-in" % [tempo, bars, roundi(bars * 4 * 60 / tempo)]

func start_take() -> void:
	if engine == null:
		return
	engine.cancel_learning()
	mappings = engine.get_mapping()
	if not engine.load_chart(tempo, bars, model.chart(lesson_index, bars)):
		preserve_error = "This lesson could not be loaded by the timing engine."
		update_footer()
		return
	take_settings = {"bpm": tempo, "bars": bars, "guidance": guidance, "source": source_id, "mapping": mappings.duplicate(true)}
	score_before = int(model.best(lesson_index, take_settings).get("points", -1))
	take_lesson_index = lesson_index
	saved_fingerprint = ""
	take_id = "%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	result_fingerprint = ""
	stage_done = false
	pulses.clear()
	recent_offsets = [[], [], []]
	var first: float = engine.start(4)
	if first < 0:
		snapshot = engine.snapshot()
		update_footer()
		return
	clear_page("stage")
	canvas = PracticeStage.new()
	canvas.guidance = guidance
	canvas.lesson_title = model.course.lessons[lesson_index].title
	canvas.lesson_bars = bars
	canvas.authored = model.course.lessons[lesson_index].events
	canvas.show_live = guidance != 2
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(canvas)
	score_hud.update_score({}, false, score_before, "COUNT-IN")

func show_pause() -> void:
	if engine != null:
		engine.stop()
		snapshot = engine.snapshot()
	clear_page("pause")
	gap(content, 0, true)
	content.add_child(label("TAKE A BREATH", 12, MUTED))
	content.add_child(label("Practice paused.", 48))
	content.add_child(label("Restart with a fresh count-in, or review the hits so far. An unfinished take doesn't change your records.", 18, MUTED, true))
	var actions := row()
	content.add_child(actions)
	actions.add_child(button("Restart with count-in", start_take, true))
	actions.add_child(button("Review this take", show_result))
	actions.add_child(button("Main menu", show_main))
	gap(content, 0, true)

func stop_take() -> void:
	if engine != null:
		engine.stop()
		snapshot = engine.snapshot()
	show_result()

func show_result() -> void:
	stage_done = true
	clear_page("result")
	result_fingerprint = ""
	result_grade_fingerprint = ""
	var stack := centered_column(12)
	stack.add_child(label("LISTEN. ADJUST. GO AGAIN.", 11, LIME))
	stack.add_child(label("%s  ·  %d BPM  ·  %d bars  ·  %s" % [model.course.lessons[lesson_index].title, tempo, bars, ["Guided", "Hide alternate bars", "Click-only"][guidance]], 11, MUTED))
	stack.add_child(label("Your take." if bool(snapshot.get("naturally_completed", false)) else "Take stopped.", 36))
	result_detail = label("", 17, Color(PAPER, 0.75), true)
	stack.add_child(result_detail)
	result_visual = ScoreReview.new()
	stack.add_child(result_visual)
	var metrics := row()
	metrics.add_theme_constant_override("separation", 38)
	for caption in ["HITS", "MISSES", "EXTRAS", "BEST COMBO"]:
		var group := VBoxContainer.new()
		var value := label("0", 26)
		result_metrics.append(value)
		group.add_child(value)
		group.add_child(label(caption, 11, MUTED))
		metrics.add_child(group)
	stack.add_child(metrics)
	stack.add_child(label("Points reward notes inside ±50 ms. Missing and extra hits lower your score.", 12, MUTED, true))
	result_best = label("", 13, LIME, true)
	stack.add_child(result_best)
	var actions := row()
	stack.add_child(actions)
	actions.add_child(button("Play again", start_take, true))
	actions.add_child(button("Slow it down", func(): tempo = maxf(30, tempo - 6); start_take()))
	actions.add_child(button("Work on one bar", func(): bars = 1; guidance = 0 if guidance == 1 else guidance; start_take()))
	actions.add_child(button("Try less help" if guidance < 2 else "Repeat click-only", func():
		if guidance == 2: start_take(); return
		guidance += 1
		if guidance == 1 and bars == 1: bars = 4
		build_prepare()))
	var next_actions := row()
	stack.add_child(next_actions)
	next_actions.add_child(button("Lesson check", show_learning_check))
	next_lesson_button = button("Next lesson", func(): show_prepare(mini(11, lesson_index + 1)))
	next_lesson_button.disabled = lesson_index >= 11 or lesson_index >= model.frontier()
	next_actions.add_child(next_lesson_button)
	next_actions.add_child(button("Practice options", func(): options_open = true; build_prepare()))
	next_actions.add_child(button("Learning path", func(): show_learn(model.frontier())))
	update_result()

func show_learning_check() -> void:
	if check_overlay != null: return
	var lesson: Dictionary = model.course.lessons[lesson_index]
	check_return = page
	modal_focus.clear()
	for control in find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
			modal_focus.append([control, control.focus_mode])
			control.focus_mode = Control.FOCUS_NONE
	check_overlay = ColorRect.new()
	check_overlay.color = Color(0.015, 0.023, 0.026, 0.9)
	check_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(check_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	check_overlay.add_child(center)
	var panel := PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color("11191b")
	background.border_color = Color(PAPER, 0.1)
	background.set_border_width_all(1)
	background.set_corner_radius_all(18)
	for side in ["left", "right", "top", "bottom"]: background.set("content_margin_" + side, 32)
	panel.add_theme_stylebox_override("panel", background)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 672
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)
	stack.add_child(label("CONNECT IT TO REAL DRUMMING", 11, LIME))
	stack.add_child(label(lesson.reading_question, 23, PAPER, true))
	for index in range(lesson.reading_choices.size()):
		stack.add_child(button(lesson.reading_choices[index], func(): answer_reading(index)))
	stage_feedback = label("Choose an answer. You can revisit this check any time.", 13, MUTED, true)
	stack.add_child(stage_feedback)
	stack.add_child(label(lesson.technique_tip, 13, PAPER, true))
	stack.add_child(label("Self-check only. MIDI cannot verify your technique.", 11, MUTED))
	var done := button("Done", close_learning_check, true)
	stack.add_child(done)
	if not smoke: done.call_deferred("grab_focus")

func close_learning_check() -> void:
	if check_overlay == null: return
	check_overlay.queue_free()
	check_overlay = null
	for item in modal_focus:
		if is_instance_valid(item[0]): item[0].focus_mode = item[1]
	modal_focus.clear()
	stage_feedback = null
	if check_return == "result": show_result()
	else: build_prepare()

func answer_reading(answer: int) -> void:
	var lesson: Dictionary = model.course.lessons[lesson_index]
	if answer == int(lesson.reading_answer):
		var previous: Dictionary = model.save.read.duplicate()
		model.save.read[lesson.version] = true
		if not model.persist():
			model.save.read = previous
			stage_feedback.text = model.error
			return
		stage_feedback.text = "That's right. " + ("Next step open." if model.cleared(lesson_index) else "Match 80% of the notes in a complete take to open the next step.")
	else:
		stage_feedback.text = "Try again. " + lesson.explanation

func update_result() -> void:
	if result_detail == null:
		return
	var complete := bool(snapshot.get("naturally_completed", false))
	var points_value := DataModel.points(snapshot, complete)
	var grade_fingerprint := JSON.stringify([points_value, snapshot.get("matched"), snapshot.get("missed"), snapshot.get("extra"), snapshot.get("best_streak")])
	if complete and grade_fingerprint != result_grade_fingerprint:
		model.record(take_id, take_lesson_index, snapshot, take_settings)
		result_grade_fingerprint = grade_fingerprint
	var comparable_attempts: Array = model.save.attempts.filter(func(attempt): return attempt.lesson == model.course.lessons[lesson_index].id and attempt.version == model.course.lessons[lesson_index].version and attempt.settings == take_settings)
	var saved := comparable_attempts.any(func(attempt):
		if attempt.id != take_id or int(attempt.points) != points_value: return false
		for key in ["matched", "on_time", "missed", "extra", "expected", "best_streak"]:
			if int(attempt[key]) != int(snapshot.get(key, 0)): return false
		return true)
	var fingerprint := JSON.stringify([grade_fingerprint, saved, model.error, model.frontier(), comparable_attempts])
	if fingerprint == result_fingerprint: return
	result_fingerprint = fingerprint
	if next_lesson_button != null:
		next_lesson_button.disabled = lesson_index >= 11 or lesson_index >= model.frontier()
	result_visual.update_score(snapshot, score_before, comparable_attempts, take_id if saved else "")
	var metric_keys := ["matched", "missed", "extra", "best_streak"]
	for index in range(result_metrics.size()): result_metrics[index].text = str(int(snapshot.get(metric_keys[index], 0)))
	var timing_count := int(snapshot.get("matched", 0))
	if not complete:
		result_detail.text = "Take stopped. Restart with a fresh count-in."
	elif points_value == 10000:
		result_detail.text = "Every note landed in the timing band. Try less visual help when it feels easy."
	elif timing_count == 0:
		result_detail.text = "No matched notes yet. Check your input, then follow the count."
	else:
		result_detail.text = "Keep the spaces even. Listen to the click and make one adjustment for your next take."
	var comparable: Dictionary = model.best(lesson_index, take_settings)
	result_best.text = ("New personal best. " if complete and saved and points_value > score_before and score_before >= 0 else "") + ("Best with these settings: %d points." % int(comparable.points) if not comparable.is_empty() else "Complete a full take to save your first record.")
	if model.error != "":
		result_best.text = model.error
	update_footer()

func show_settings() -> void:
	clear_page("settings")
	settings_panel = SettingsPanel.new()
	settings_panel.controller = self
	settings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(settings_panel)
	canvas = settings_panel.kit_canvas
	mapping_label = settings_panel.mapping_label
	kit_signal = settings_panel.signal_label
	source_option = settings_panel.source_option
	refresh_sources()
	refresh_mapping()
	settings_panel.refresh_state()

func refresh_sources() -> void:
	if source_option == null:
		return
	source_option.clear()
	source_option.add_item("Keyboard / no MIDI input")
	source_ids = [""]
	if engine != null:
		for source in engine.sources():
			source_option.add_item(str(source.name))
			source_ids.append(str(source.id))
	var selected := source_ids.find(source_id)
	if selected < 0:
		select_source(0)
		selected = 0
	source_option.select(selected)

func select_source(index: int) -> void:
	if engine == null:
		return
	if engine.connect_source(source_ids[index]):
		source_id = str(source_ids[index])
	else:
		source_id = ""
	checked.clear()
	refresh_mapping()

func begin_learning() -> void:
	if engine != null and engine.learn_pad(selected_pad):
		kit_signal.text = "Strike your %s once to add its MIDI note." % PAD_NAMES[selected_pad].to_lower()
	elif kit_signal != null:
		kit_signal.text = "Choose your MIDI kit first."
	refresh_mapping()

func select_pad(pad: int) -> void:
	if engine != null:
		engine.cancel_learning()
	selected_pad = pad
	refresh_mapping()

func refresh_mapping() -> void:
	if engine != null:
		mappings = engine.get_mapping()
		snapshot = engine.snapshot()
	if mapping_label != null:
		mapping_label.text = "%s  /  MIDI notes %s" % [PAD_NAMES[selected_pad], ", ".join(mappings[selected_pad].map(func(value): return str(value))) ]
	if canvas != null and page == "settings":
		canvas.selected_pad = selected_pad
		canvas.checked = checked
		canvas.learn_pad = int(snapshot.get("pending_pad", -1))
		canvas.queue_redraw()
	if settings_panel != null: settings_panel.refresh_state()

func save_settings() -> void:
	model.save.settings = {"volume": volume, "monitoring": monitoring, "mapping": mappings}
	model.persist()
	update_footer()

func _process(_delta: float) -> void:
	if smoke or engine == null or root_stack == null:
		return
	var now: float = engine.get_host_time()
	if now >= sources_refresh_at:
		sources_refresh_at = now + 1.0
		engine.sources() # Native enumeration also detects loss of the selected port.
		if page == "settings": refresh_sources()
	var hits: Array = engine.poll_hits()
	for hit in hits:
		# Arrival time animates feedback; native host time remains authoritative for grading.
		var pulse: Dictionary = hit.duplicate()
		pulse.host_time = now
		pulses.append(pulse)
		if pulses.size() > 48:
			pulses.pop_front()
		var pad := int(hit.pad)
		if pad >= 0 and (source_id == "" or str(hit.get("source_id", "")) == source_id) and pad not in checked:
			checked.append(pad)
		if int(hit.get("judgment", 0)) in [1, 2, 3] and pad >= 0:
			recent_offsets[pad].append({"offset": float(hit.offset_ms), "time": now})
			if recent_offsets[pad].size() > 12: recent_offsets[pad].pop_front()
		if bool(hit.get("mapping_changed", false)):
			checked.clear()
			if pad >= 0: checked.append(pad)
			mappings = engine.get_mapping()
			save_settings()
			if page == "settings": refresh_mapping()
		if page == "settings":
			kit_signal.text = "%s · velocity %d · %s" % ["MIDI %d" % int(hit.note) if int(hit.note) >= 0 else "Keyboard preview", int(hit.velocity), PAD_NAMES[pad] if pad >= 0 else "unmapped"]
	pulses = pulses.filter(func(pulse): return now - float(pulse.host_time) < 0.42)
	snapshot = engine.snapshot()
	if bool(snapshot.get("naturally_completed", false)) and take_id != "":
		var grade_fingerprint := JSON.stringify([snapshot.get("on_time"), snapshot.get("matched"), snapshot.get("missed"), snapshot.get("extra"), snapshot.get("best_streak")])
		if grade_fingerprint != saved_fingerprint and now >= save_retry_at:
			save_retry_at = now + 1.0
			if model.record(take_id, take_lesson_index, snapshot, take_settings): saved_fingerprint = grade_fingerprint
	if str(snapshot.get("source_id", "")) != source_id:
		source_id = str(snapshot.get("source_id", ""))
		checked.clear()
		if page == "settings": refresh_sources()
	if canvas != null and page in ["stage", "settings"]:
		canvas.current_host = now
		canvas.pulses = pulses
		if page == "stage":
			canvas.elapsed = render_elapsed(snapshot, now)
			canvas.bpm = tempo
			canvas.events = engine.get_events()
			canvas.bias = snapshot.get("bias", [])
			canvas.active = bool(snapshot.get("running", false))
			canvas.completed = bool(snapshot.get("naturally_completed", false))
		elif page == "settings":
			canvas.checked = checked
			canvas.learn_pad = int(snapshot.get("pending_pad", -1))
		canvas.queue_redraw()
	if page == "stage":
		var elapsed: float = render_elapsed(snapshot, now)
		score_hud.update_score(snapshot, guidance != 2 and elapsed >= 0, score_before,
			"COUNT-IN" if elapsed < 0 else "RESULTS AFTER THE PHRASE")
		if bool(snapshot.get("completed", false)) and not stage_done:
			show_result()
	elif page == "result":
		update_result()
	update_footer()

static func render_elapsed(state: Dictionary, now: float) -> float:
	return now - float(state.get("practice_start", now)) if bool(state.get("running", false)) else float(state.get("elapsed_seconds", 0))

func timing_feedback(now: float) -> String:
	var messages: Array = []
	for pad in range(3):
		var samples: Array = recent_offsets[pad].filter(func(sample): return now - float(sample.time) < 16)
		if samples.size() < 6 or now - float(samples.back().time) > 4:
			continue
		var offsets: Array = samples.map(func(sample): return float(sample.offset))
		offsets.sort()
		var middle := offsets.size() / 2
		var median: float = (float(offsets[middle - 1]) + float(offsets[middle])) / 2.0 if offsets.size() % 2 == 0 else float(offsets[middle])
		var deviations: Array = offsets.map(func(offset): return absf(float(offset) - median))
		deviations.sort()
		if float(deviations[middle]) > 25:
			messages.append("%s: keep the spaces even" % PAD_NAMES[pad])
			continue
		messages.append("%s: %s" % [PAD_NAMES[pad], "steady" if absf(median) < 18 else "%d ms %s" % [roundi(absf(median)), "early" if median < 0 else "late"]])
	return "   ·   ".join(messages) if not messages.is_empty() else "Listen to the click. Keep the spaces even."

func _input(event: InputEvent) -> void:
	if page != "stage" or engine == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	var pad: int = int({KEY_A: 0, KEY_S: 1, KEY_SPACE: 2}.get(event.physical_keycode, -1))
	if pad >= 0:
		engine.keyboard_hit(pad, 48 if event.shift_pressed else 108)
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if check_overlay != null: close_learning_check()
		elif page == "stage": show_pause()
		else: show_main()
		get_viewport().set_input_as_handled()
		return
	if check_overlay != null: return
	if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:
		return
	if event.keycode == KEY_ENTER and page in ["prepare", "result", "pause"]:
		start_take()
		get_viewport().set_input_as_handled()
		return
	if engine != null and page in ["prepare", "settings"]:
		var pad: int = int({KEY_A: 0, KEY_S: 1, KEY_SPACE: 2}.get(event.physical_keycode, -1))
		if pad >= 0:
			engine.keyboard_hit(pad, 48 if event.shift_pressed else 108)
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and engine != null:
		engine.stop()


var smoke_checks := 0
var smoke_failed := false

func verify(condition: bool, description: String) -> bool:
	smoke_checks += 1
	if not condition:
		printerr("DRUMX_SMOKE_FAILED: " + description)
		smoke_failed = true
	return condition

func smoke_test() -> void:
	# Explicit checks and side effects run in release exports. This path never
	# loads or writes real progress, selects a MIDI source, or opens audio output.
	model.blocked = true
	var native_required := "--smoke-test" in OS.get_cmdline_user_args()
	for index in range(12):
		var authored: Array = model.course.lessons[index].events
		var chart: Array = model.chart(index, 16)
		verify(chart.size() == authored.size() * 16, "authored repeat count")
		for event in chart:
			verify(typeof(event.pad) == TYPE_INT and float(event.beat) >= 0 and float(event.beat) < 64 and int(event.pad) in [0, 1, 2], "normalized chart event")
		if engine != null:
			var loaded: bool = engine.load_chart(float(model.course.lessons[index].bpm), 16, chart)
			verify(loaded, "native chart load")
			var native_events: Array = engine.get_events()
			verify(native_events.size() == chart.size(), "native event count")
			for i in range(mini(native_events.size(), chart.size())):
				verify(int(native_events[i].pad) == int(chart[i].pad) and absf(float(native_events[i].time_seconds) - float(chart[i].beat) * 60.0 / float(model.course.lessons[index].bpm)) < 0.000001, "native event timing")
	verify(DataModel.points({"expected": 64, "on_time": 1, "extra": 0}, false) == 156, "live points use whole phrase")
	verify(DataModel.stars(9999, false) == 4, "incomplete take has no fifth star")
	verify(DataModel.points({"expected": 64, "on_time": 64, "extra": 1}, true) < 10000, "extras reduce points")
	verify(DataModel.stars(10000, true) == 5, "complete perfect score")
	verify(render_elapsed({"running": true, "practice_start": 104.0, "elapsed_seconds": 0.0}, 100.0) == -4.0, "visual count-in uses signed native host clock")
	verify(render_elapsed({"running": false, "elapsed_seconds": 16.0}, 999.0) == 16.0, "closed take rendering holds final elapsed")
	verify(model.valid_save(model.save), "empty progress is valid")
	var invalid: Dictionary = model.save.duplicate(true)
	invalid.attempts = [{"id": "broken"}]
	verify(not model.valid_save(invalid), "malformed attempt rejected")
	invalid = model.save.duplicate(true)
	invalid.settings = {"volume": "bad", "mapping": [[42], [38], [36]]}
	verify(not model.valid_save(invalid), "invalid settings rejected")
	var clean_save: Dictionary = model.save.duplicate(true)
	var evidence := {"id": "fixture", "lesson": model.course.lessons[0].id, "version": model.course.lessons[0].version,
		"settings": {"bpm": 60, "bars": 16, "guidance": 0, "source": "", "mapping": mappings},
		"points": 5000, "matched": 60, "on_time": 32, "missed": 4, "extra": 0, "expected": 64, "best_streak": 6}
	verify(model.valid_attempt(evidence), "complete late-heavy take is valid")
	model.save.attempts = [evidence]
	verify(model.cleared(0), "matched-note evidence opens ordinary next step independently of stars")
	evidence = evidence.duplicate(true)
	evidence.id = "chapter"
	evidence.lesson = model.course.lessons[3].id
	evidence.version = model.course.lessons[3].version
	model.save.attempts = [evidence]
	verify(not model.cleared(3), "chapter transition needs reading check")
	model.save.read[evidence.version] = true
	verify(model.cleared(3), "chapter transition opens after reading evidence")
	var round_trip = JSON.parse_string(JSON.stringify(model.save))
	verify(model.valid_save(round_trip), "completed attempts survive JSON number conversion")
	var broken = round_trip.duplicate(true)
	broken.attempts[0].on_time = 99
	verify(not model.valid_save(broken), "inconsistent scoring evidence rejected")
	broken = round_trip.duplicate(true)
	broken.attempts.append(broken.attempts[0])
	verify(not model.valid_save(broken), "duplicate take IDs rejected")
	model.save = clean_save
	var parsed_mapping: Array = JSON.parse_string(JSON.stringify(mappings))
	verify(DataModel.valid_mapping(parsed_mapping), "reloaded MIDI map valid")
	mappings = DataModel.normalized_mapping(parsed_mapping)
	verify(typeof(mappings[0][0]) == TYPE_INT, "reloaded MIDI alias type")
	# Isolated persistence fixture. No reads or writes use the production save path.
	var disk_fixture = DataModel.new()
	disk_fixture.load_course()
	disk_fixture.save_path = "user://.smoke-progress-%d-%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	var disk_settings: Dictionary = {"bpm": 60, "bars": 16, "guidance": 0, "source": "", "mapping": mappings}
	var disk_score: Dictionary = {"naturally_completed": true, "expected": 64, "matched": 64, "missed": 0, "on_time": 64, "extra": 0, "best_streak": 64}
	verify(disk_fixture.record("isolated-take", 0, disk_score, disk_settings), "write isolated completed attempt")
	disk_score.matched = 63
	disk_score.missed = 1
	disk_score.on_time = 63
	disk_score.best_streak = 63
	verify(disk_fixture.record("isolated-take", 0, disk_score, disk_settings), "atomic replacement of existing isolated save")
	var disk_reopen = DataModel.new()
	disk_reopen.load_course()
	disk_reopen.save_path = disk_fixture.save_path
	disk_reopen.load_progress()
	verify(not disk_reopen.blocked and disk_reopen.save.attempts.size() == 1 and int(disk_reopen.save.attempts[0].points) == 9843, "reload corrected same-ID take without duplicates")
	var corrupt_file := FileAccess.open(disk_fixture.save_path, FileAccess.WRITE)
	if verify(corrupt_file != null, "open isolated corrupt-file fixture"):
		corrupt_file.store_string("{broken")
		corrupt_file.close()
		var corrupt_reopen = DataModel.new()
		corrupt_reopen.load_course()
		corrupt_reopen.save_path = disk_fixture.save_path
		corrupt_reopen.load_progress()
		verify(corrupt_reopen.blocked and not corrupt_reopen.persist() and FileAccess.get_file_as_string(disk_fixture.save_path) == "{broken", "corrupt file is preserved and blocks overwrite")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(disk_fixture.save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(disk_fixture.save_path + ".tmp"))
	var projection = PracticeStage.new()
	var visual_fixture = JSON.parse_string(FileAccess.get_file_as_string("res://data/visual-baseline.json"))
	if verify(visual_fixture is Dictionary, "native visual fixture loads in packaged build"):
		var visual_result := VisualContract.compare_stage(projection, visual_fixture)
		smoke_checks += int(visual_result.checks)
		for failure in visual_result.failures:
			verify(false, str(failure))
	projection.free()
	var notation_result := NotationContract.new().run_checks(get_tree().root)
	smoke_checks += int(notation_result.checks)
	verify(notation_result.failures == 0, "native notation event/voice contracts")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/BigRusty/manifest.json"))
	if verify(manifest is Array and manifest.size() == 24, "sample manifest count"):
		for entry in manifest:
			var bytes := FileAccess.get_file_as_bytes("res://assets/" + str(entry.file))
			verify(bytes.size() > 4 and bytes.slice(0, 4).get_string_from_ascii() == "fLaC", "original bundled FLAC bytes")
	if native_required:
		verify(engine != null, "native DrumxEngine binding exists")
	if engine != null:
		var sample_result: bool = engine.load_sample_bank("res://assets/BigRusty", false)
		verify(sample_result and bool(engine.snapshot().get("samples_ready", false)), "native decodes all24 FLAC without audio output")
		var mapped: bool = engine.set_mapping(mappings)
		verify(mapped, "native accepts reloaded normalized aliases")
	setup_theme()
	build_shell()
	show_main()
	await get_tree().process_frame
	if engine != null:
		smoke = false
		_process(0)
		smoke = true
	verify(root_stack.get_combined_minimum_size().y <= size.y - 48 and root_stack.get_combined_minimum_size().x <= size.x - 88, "main content fits default viewport")
	show_learn(0)
	await get_tree().process_frame
	if engine != null:
		smoke = false
		_process(0)
		smoke = true
	verify(root_stack.get_combined_minimum_size().y <= size.y - 48 and root_stack.get_combined_minimum_size().x <= size.x - 88, "learn content fits default viewport")
	build_prepare()
	await get_tree().process_frame
	if engine != null:
		smoke = false
		_process(0)
		smoke = true
	verify(root_stack.get_combined_minimum_size().y <= size.y - 48 and root_stack.get_combined_minimum_size().x <= size.x - 88, "prepare content fits default viewport")
	show_settings()
	await get_tree().process_frame
	if engine != null:
		smoke = false
		_process(0)
		smoke = true
	verify(root_stack.get_combined_minimum_size().y <= size.y - 48 and root_stack.get_combined_minimum_size().x <= size.x - 88, "settings content fits default viewport")
	# Inspect every menu at the supported minimum; exercise modal focus isolation.
	get_window().size = Vector2i(1020, 780)
	for destination in ["main", "learn", "prepare", "result", "settings"]:
		match destination:
			"main": show_main()
			"learn": show_learn(11)
			"prepare": build_prepare()
			"result": show_result()
			"settings": show_settings()
		await get_tree().process_frame
		if engine != null:
			smoke = false
			_process(0)
			smoke = true
		verify(root_stack.get_combined_minimum_size().x <= size.x - 40 and root_stack.get_combined_minimum_size().y <= size.y - 40, destination + " fits minimum logical viewport")
	build_prepare()
	show_learning_check()
	verify(not modal_focus.is_empty() and modal_focus.all(func(item): return item[0].focus_mode == Control.FOCUS_NONE), "quiz prevents keyboard focus reaching underlying actions")
	close_learning_check()
	verify(check_overlay == null and modal_focus.is_empty() and back.focus_mode != Control.FOCUS_NONE, "closing quiz restores shell focus")
	var repair_evidence: Dictionary = evidence.duplicate(true)
	repair_evidence.settings.bars = 1
	repair_evidence.lesson = model.course.lessons[0].id
	repair_evidence.version = model.course.lessons[0].version
	repair_evidence.expected = 4
	repair_evidence.matched = 4
	repair_evidence.missed = 0
	repair_evidence.on_time = 2
	repair_evidence.best_streak = 2
	verify(model.valid_attempt(repair_evidence), "one-bar repair records are valid")
	model.save.attempts = [repair_evidence]
	verify(not model.cleared(0), "one-bar repair cannot unlock another lesson")
	model.save = clean_save
	if smoke_failed:
		get_tree().quit(1)
	else:
		print("DRUMX_SMOKE_OK %d shared frontend/course/core/asset checks; native=%s" % [smoke_checks, engine != null])
		get_tree().quit(0)
