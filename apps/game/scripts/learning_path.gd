extends Control

# DrumxCourseMenuView's composition in logical points. Progression stays in the
# existing model; inspecting a future lesson does not select it for practice.
const Menu = preload("res://scripts/main_menu.gd")
const DataModel = preload("res://scripts/game_data.gd")
const INK = Color(0.047, 0.063, 0.071, 1)
const PAPER = Color(0.94, 0.95, 0.91, 1)
const LIME = Color(0.79, 0.91, 0.49, 1)
const MUTED = Color(0.57, 0.65, 0.64, 1)
const CHAPTERS_PER_PAGE := 3

signal play_requested(index: int)
signal selected(index: int)

var model: Object
var featured_index := 0
var chapter_page := 0
var composition := Control.new()
var _title: Label
var _subtitle: Label
var _progress: Label
var _step: Label
var _lesson_title: Label
var _objective: Label
var _step_hint: Label
var _trail_title: Label
var _trail_hint: Label
var _play: PathButton
var _previous_page: PathButton
var _next_page: PathButton
var _stars: CourseStars
var _path_divider := ColorRect.new()
var _chapters: Array[Label] = []
var _nodes: Array[PathButton] = []
var _labels: Array[Dictionary] = []


class PathButton extends Button:
	var primary := false
	var navigation_control := false
	var inspected := false
	var cleared := false
	var available := true
	var drawing_scale := 1.0
	var hovered := false
	var title_font: Font
	signal navigation(offset: int)
	signal page_navigation(offset: int)

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Real button text remains available to assistive technology. Only its
		# theme drawing is suppressed, leaving the authored control below.
		add_theme_font_size_override("font_size", 1)
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color"]:
			add_theme_color_override(state, Color.TRANSPARENT)
		mouse_entered.connect(func(): hovered = true; queue_redraw())
		mouse_exited.connect(func(): hovered = false; queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo or disabled:
			return
		if not primary and event.keycode in [KEY_LEFT, KEY_RIGHT]:
			navigation.emit(-1 if event.keycode == KEY_LEFT else 1)
			accept_event()
		elif event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
			page_navigation.emit(-1 if event.keycode == KEY_PAGEUP else 1)
			accept_event()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		if title_font == null or drawing_scale <= 0:
			return
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * drawing_scale)
		var area := Rect2(Vector2.ZERO, size / drawing_scale)
		var active := hovered or is_pressed() or has_focus()
		var shape := StyleBoxFlat.new()
		shape.set_corner_radius_all(8)
		if primary:
			shape.bg_color = Color(PAPER, 0.08) if disabled else Color(LIME, 0.76 if is_pressed() else 1.0 if active else 0.91)
		else:
			shape.bg_color = Color(LIME, 0.14) if inspected else Color(PAPER, 0.07 if active else 0.025)
		shape.border_color = LIME if has_focus() or inspected else Color(PAPER, 0.3 if active else 0.10)
		shape.set_border_width_all(2 if has_focus() else 1)
		draw_style_box(shape, area.grow(-1))
		var color := INK if primary and not disabled else PAPER if available and not disabled else MUTED
		var point_size := 18 if primary else 13 if navigation_control else 17
		var top := area.size.y / 2 - (12 if primary else 11)
		draw_string(title_font, Vector2(8, top + title_font.get_ascent(point_size)), text,
			HORIZONTAL_ALIGNMENT_CENTER, area.size.x - 16, point_size, color)
		if not primary and not navigation_control:
			var width := 20.0 if cleared else 12.0
			var marker := StyleBoxFlat.new()
			marker.set_corner_radius_all(1)
			marker.bg_color = LIME if cleared else Color(LIME, 0.5) if available else Color(MUTED, 0.22)
			draw_style_box(marker, Rect2((area.size.x - width) / 2, area.size.y - 9, width, 2.5))
		draw_set_transform(Vector2.ZERO)


class CourseStars extends Control:
	var step_state := "YOUR NEXT STEP"
	var stars := 0
	var has_record := false
	var conditions := "Build toward five stars."
	var label_font: Font
	var detail_font: Font

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var scale := minf(size.x / 290, size.y / 146)
		if scale <= 0 or label_font == null or detail_font == null:
			return
		draw_set_transform(Vector2((size.x - 290 * scale) / 2, 0), 0, Vector2.ONE * scale)
		var header_size := maxi(10, ceili(11 / scale))
		draw_string(label_font, Vector2(0, 4 + label_font.get_ascent(header_size)),
			step_state, HORIZONTAL_ALIGNMENT_CENTER, 290, header_size, LIME)
		for index in range(5):
			var center := Vector2(29 + index * 58, 65)
			var points := PackedVector2Array()
			for point in range(10):
				var angle := -PI / 2 + float(point) * PI / 5
				var radius := 19.0 if point % 2 == 0 else 8.5
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			if index < stars:
				draw_colored_polygon(points, LIME)
			else:
				points.append(points[0])
				draw_polyline(points, Color(PAPER, 0.18), 1, true)
		draw_string(detail_font, Vector2(0, 112 + detail_font.get_ascent(14)),
			"BEST  ·  " + conditions if has_record else "No completed take yet", HORIZONTAL_ALIGNMENT_CENTER, 290, 12, MUTED)
		draw_set_transform(Vector2.ZERO)


func configure(course_model: Object, index: int) -> void:
	model = course_model
	var count: int = model.course.lessons.size() if model != null else 0
	featured_index = clampi(index, 0, maxi(0, count - 1))
	if is_node_ready():
		_refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	composition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(composition)
	_path_divider.color = Color(PAPER, 0.09)
	_path_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	composition.add_child(_path_divider)
	_title = _label("Learn.", 38, PAPER, 700)
	_subtitle = _label("", 14, MUTED)
	_progress = _label("", 12, MUTED)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_step = _label("", 11, LIME, 500)
	_lesson_title = _label("", 36, PAPER, 600, 2)
	_objective = _label("", 16, MUTED, 400, 3)
	_step_hint = _label("", 12, MUTED, 400, 2)
	_trail_title = _label("YOUR LEARNING PATH", 11, MUTED, 500)
	_trail_hint = _label("", 11, MUTED)
	_trail_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_previous_page = _page_button("Previous", -1)
	_next_page = _page_button("Next", 1)
	_play = PathButton.new()
	_play.primary = true
	_play.title_font = Menu.make_font(600)
	_play.pressed.connect(_play_featured)
	composition.add_child(_play)
	_stars = CourseStars.new()
	_stars.label_font = Menu.make_font(500)
	_stars.detail_font = Menu.make_font(500)
	composition.add_child(_stars)
	resized.connect(_layout)
	_refresh()


func _page_button(title: String, direction: int) -> PathButton:
	var control := PathButton.new()
	control.text = title
	control.navigation_control = true
	control.title_font = Menu.make_font(500)
	control.accessibility_name = title + " chapters"
	control.pressed.connect(func(): _turn_page(direction))
	composition.add_child(control)
	return control


func _label(value: String, point_size: int, color: Color, weight: int = 400, lines: int = 1) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Menu.make_font(weight))
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", color)
	label.clip_text = true
	label.max_lines_visible = lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if lines > 1:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	composition.add_child(label)
	_labels.append({"view": label, "size": point_size})
	return label


func _refresh() -> void:
	if model == null or model.course.lessons.is_empty():
		return
	var course: Dictionary = model.course
	if _nodes.size() != course.lessons.size():
		_build_path(course)
	var lesson: Dictionary = course.lessons[featured_index]
	chapter_page = int(lesson.chapter) / CHAPTERS_PER_PAGE
	var frontier: int = model.frontier()
	var available := featured_index <= frontier
	var complete: bool = model.cleared(featured_index)
	_subtitle.text = "Foundations  /  %d lessons in rhythm, coordination and rudiments" % course.lessons.size()
	_stars.step_state = "CHECKPOINT EARNED" if complete else "LOCKED" if not available else "YOUR NEXT STEP" if featured_index == frontier else "AVAILABLE TO PLAY"
	var total_cleared := 0
	for index in range(course.lessons.size()):
		if model.cleared(index): total_cleared += 1
	_progress.text = "%d / %d steps complete" % [total_cleared, course.lessons.size()]
	_step.text = "STEP %02d  /  %s" % [featured_index + 1, str(course.chapters[int(lesson.chapter)]).to_upper()]
	_lesson_title.text = lesson.title
	_objective.text = lesson.objective
	_play.text = "Step locked" if not available else "Play this step again" if complete else "Play this step"
	_play.disabled = not available
	_play.available = available
	_play.accessibility_name = "%s. %s." % [_play.text, lesson.title]
	_step_hint.text = lock_reason(featured_index) if not available else "Step complete. Repeat for a steadier score, or explore your next step." if complete else _available_hint(featured_index)
	_play.tooltip_text = _step_hint.text
	var best: Dictionary = model.best(featured_index)
	_stars.conditions = "%d BPM · %s" % [int(best.settings.bpm), ["Guided", "Hidden bars", "From memory"][int(best.settings.guidance)]] if not best.is_empty() else "72 BPM · guided checkpoint" if featured_index == 0 else "Build toward five stars."
	_stars.has_record = not best.is_empty()
	_stars.stars = DataModel.stars(int(best.get("points", 0)), true)
	_stars.accessibility_name = "%d of 5 stars recorded for %s. Build toward five stars." % [_stars.stars, lesson.title] if _stars.has_record else "Build toward five stars for %s." % lesson.title
	_stars.accessibility_description = "Best recorded score across saved practice conditions. Stars are separate from step completion." if _stars.has_record else "No completed take recorded for this lesson yet."
	_stars.tooltip_text = _stars.conditions + ". " + _stars.accessibility_description
	for index in range(_nodes.size()):
		var node := _nodes[index]
		var definition: Dictionary = course.lessons[index]
		node.inspected = index == featured_index
		node.available = index <= frontier
		node.cleared = model.cleared(index)
		var state := "Step complete" if node.cleared else "Available" if node.available else "Locked"
		var detail: String = definition.objective if node.available else lock_reason(index)
		node.accessibility_name = "Inspect step %d. %s. %s." % [index + 1, definition.title, state]
		node.accessibility_description = detail
		node.tooltip_text = "%s. %s. %s" % [definition.title, state, detail]
		node.focus_neighbor_top = node.get_path_to(_play) if not _play.disabled else NodePath()
		node.queue_redraw()
	_play.focus_neighbor_bottom = _play.get_path_to(_nodes[featured_index])
	_play.queue_redraw()
	_stars.queue_redraw()
	_layout()


func _build_path(course: Dictionary) -> void:
	# Chapters page in groups of three, preserving readable note-sized targets as
	# the course grows. Inspection never changes the selected practice lesson.
	for node in _nodes:
		composition.remove_child(node)
		node.queue_free()
	for chapter in _chapters:
		_labels = _labels.filter(func(item): return item["view"] != chapter)
		composition.remove_child(chapter)
		chapter.queue_free()
	_nodes.clear()
	_chapters.clear()
	for index in range(course.chapters.size()):
		_chapters.append(_label("%d  %s" % [index + 1, course.chapters[index]], 11, MUTED, 500))
	for index in range(course.lessons.size()):
		var node := PathButton.new()
		node.text = "%02d" % (index + 1)
		node.title_font = Menu.make_font(600)
		node.pressed.connect(func(): _inspect(index))
		node.navigation.connect(func(offset): _focus_step(index + offset))
		node.page_navigation.connect(_turn_page)
		composition.add_child(node)
		_nodes.append(node)


func _inspect(index: int) -> void:
	featured_index = index
	_refresh()
	selected.emit(index)


func _focus_step(index: int) -> void:
	if _nodes.is_empty(): return
	var target := clampi(index, 0, _nodes.size() - 1)
	_inspect(target)
	_nodes[target].grab_focus()


func _turn_page(direction: int) -> void:
	if model == null: return
	var last_page := maxi(0, ceili(float(model.course.chapters.size()) / CHAPTERS_PER_PAGE) - 1)
	var target_page := clampi(chapter_page + direction, 0, last_page)
	if target_page == chapter_page: return
	var first_chapter := target_page * CHAPTERS_PER_PAGE
	for index in range(model.course.lessons.size()):
		if int(model.course.lessons[index].chapter) == first_chapter:
			_focus_step(index)
			return


func _play_featured() -> void:
	if model != null and featured_index <= int(model.frontier()):
		play_requested.emit(featured_index)


func _has_qualifying_take(index: int) -> bool:
	return bool(model.readiness_status(index).get("checkpoint", false))


func _needs_reading(index: int) -> bool:
	return model.needs_reading(index) and not bool(model.save.read.get(model.course.lessons[index].version, false))


func lock_reason(index: int) -> String:
	if model == null or index <= int(model.frontier()): return ""
	var prerequisite: int = model.frontier()
	var title: String = model.course.lessons[prerequisite].title
	if prerequisite == 0:
		return "Build two strong guided takes at 72 BPM in Find the pulse. Keep the same kit setup for both."
	if _needs_reading(prerequisite) and _has_qualifying_take(prerequisite):
		return "Pass the reading check in %s." % title
	return "In %s: %s" % [title, model.lesson_requirement(prerequisite)]


func _available_hint(index: int) -> String:
	if index == 0: return "Start at a coached pace. Two strong guided takes at 72 BPM open your next step."
	if _needs_reading(index) and _has_qualifying_take(index):
		return "Playing check complete. Pass this lesson's reading check to open the next chapter."
	return model.lesson_requirement(index)


func _layout() -> void:
	if _play == null or size.x <= 0 or size.y <= 0:
		return
	var margin := maxf(24, minf(112, size.x * 0.045))
	var available_width := maxf(1, size.x - margin * 2)
	var scale := minf(1.4, maxf(0.85, minf(available_width / 920, (size.y - 32) / 548)))
	var width := minf(1640, minf(available_width, maxf(920 * scale, size.x * 0.86)))
	var height := 548 * scale
	composition.position = (size - Vector2(width, height)) / 2
	composition.size = Vector2(width, height)
	for item in _labels:
		item["view"].add_theme_font_size_override("font_size", maxi(11, roundi(float(item["size"]) * scale)))
	var left_width := minf(width * 0.64, 780 * scale)
	_place(_title, 0, 0, width * 0.72, 49, scale)
	_place(_subtitle, 2 * scale, 54, width * 0.75, 22, scale)
	_place(_progress, width - 236 * scale, 18, 236 * scale, 22, scale)
	_place(_step, 2 * scale, 113, left_width, 20, scale)
	_place(_lesson_title, 0, 141, left_width, 90, scale)
	_place(_objective, 2 * scale, 235, left_width - 12 * scale, 64, scale)
	_place(_play, 0, 319, 250 * scale, 54, scale)
	_place(_step_hint, 270 * scale, 323, width - 270 * scale, 46, scale)
	var star_width := minf(340 * scale, width - left_width - 32 * scale)
	_place(_stars, width - star_width, 155, star_width, 146, scale)
	_place(_path_divider, 0, 393, width, 1, scale)
	_place(_trail_title, 2 * scale, 416, 240 * scale, 20, scale)
	_place(_trail_hint, width - 460 * scale, 416, 230 * scale, 24, scale)
	_place(_previous_page, width - 224 * scale, 410, 106 * scale, 32, scale)
	_place(_next_page, width - 106 * scale, 410, 106 * scale, 32, scale)
	var first_chapter := chapter_page * CHAPTERS_PER_PAGE
	var last_chapter := mini(first_chapter + CHAPTERS_PER_PAGE, _chapters.size())
	_trail_hint.text = "Chapters %d-%d of %d" % [first_chapter + 1, last_chapter, _chapters.size()]
	_previous_page.disabled = chapter_page == 0
	_next_page.disabled = last_chapter >= _chapters.size()
	for control in [_previous_page, _next_page]:
		control.drawing_scale = scale
		control.queue_redraw()
	var group_gap := 28 * scale
	var columns := mini(CHAPTERS_PER_PAGE, _chapters.size())
	var group_width := (width - group_gap * maxf(0, columns - 1)) / maxf(1, columns)
	for chapter in range(_chapters.size()):
		var visible_chapter := chapter >= first_chapter and chapter < last_chapter
		_chapters[chapter].visible = visible_chapter
		var group_x := (chapter - first_chapter) * (group_width + group_gap)
		_place(_chapters[chapter], group_x, 448, group_width, 20, scale)
		var indices: Array[int] = []
		for index in range(_nodes.size()):
			if int(model.course.lessons[index].chapter) == chapter: indices.append(index)
		var gap := 8 * scale
		var node_width := (group_width - gap * maxi(0, indices.size() - 1)) / maxi(1, indices.size())
		for offset in range(indices.size()):
			var node := _nodes[indices[offset]]
			node.visible = visible_chapter
			_place(node, group_x + offset * (node_width + gap), 482, node_width, 54, scale)
			node.drawing_scale = scale
			node.queue_redraw()
	_play.drawing_scale = scale
	_play.queue_redraw()
	_stars.queue_redraw()


func _place(view: Control, x: float, top: float, width: float, height: float, scale: float) -> void:
	view.position = Vector2(x, top * scale)
	view.size = Vector2(width, height * scale)
