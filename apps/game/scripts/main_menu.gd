extends Control

# Direct transcription of DrumxMainMenuView's authored coordinates and sizing.
# Every Button keeps a real, untransformed layout/hit rectangle in logical units.
const INK = Color(0.047, 0.063, 0.071, 1)
const PAPER = Color(0.94, 0.95, 0.91, 1)
const LIME = Color(0.79, 0.91, 0.49, 1)
const MUTED = Color(0.57, 0.65, 0.64, 1)
const INTER = preload("res://assets/fonts/Inter.ttf")
const DRUM = preload("res://assets/main-menu-drum.svg")
signal continued
signal learn_requested
signal settings_requested

static func make_font(weight: int = 400) -> Font:
	if OS.get_name() == "macOS":
		var font := SystemFont.new()
		font.font_names = PackedStringArray([".AppleSystemUIFont", "SF Pro Display", "Helvetica Neue"])
		font.font_weight = weight
		return font
	var font := FontVariation.new()
	font.base_font = INTER
	font.variation_opentype = {"wght": float(weight), "opsz": 24.0}
	return font

class MenuAction extends Button:
	var primary := false
	var subtitle := ""
	var selected := false
	var drawing_scale := 1.0
	var hovered := false
	var title_font: Font
	var detail_font: Font
	signal navigation(offset: int)
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_ALL
		add_theme_font_size_override("font_size", 1)
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
			add_theme_color_override(state, Color.TRANSPARENT)
		mouse_entered.connect(func(): hovered = true; queue_redraw())
		mouse_exited.connect(func(): hovered = false; queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and not disabled:
			if event.keycode in [KEY_UP, KEY_DOWN]:
				navigation.emit(-1 if event.keycode == KEY_UP else 1)
				accept_event()
			elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				pressed.emit()
				accept_event()
	func _draw() -> void:
		if title_font == null:
			return
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * drawing_scale)
		var area := Rect2(Vector2.ZERO, size / drawing_scale)
		var active := not disabled and (hovered or selected or has_focus())
		var shape := StyleBoxFlat.new()
		shape.set_corner_radius_all(8)
		if disabled:
			shape.bg_color = Color(PAPER, 0.035)
			draw_style_box(shape, area.grow(-2))
		elif primary:
			shape.bg_color = Color(LIME, 0.76 if is_pressed() else 1.0 if active else 0.91)
			draw_style_box(shape, area.grow(-2))
		elif active:
			shape.bg_color = Color(PAPER, 0.1 if is_pressed() else 0.045)
			draw_style_box(shape, area.grow(-2))
		if not disabled and (selected or has_focus()):
			var stripe := StyleBoxFlat.new()
			stripe.bg_color = Color(LIME, 0.6 if primary else 0.9)
			stripe.set_corner_radius_all(2)
			var inset := 19.0 if primary else 14.0
			draw_style_box(stripe, Rect2(0, inset, 3, area.size.y - inset * 2))
			if primary:
				var ring := StyleBoxFlat.new()
				ring.draw_center = false
				ring.set_border_width_all(1)
				ring.border_color = Color(LIME, 0.34)
				ring.set_corner_radius_all(10)
				draw_style_box(ring, area.grow(-0.5))
		var foreground: Color = Color(MUTED, 0.7) if disabled else INK if primary else PAPER if active else MUTED
		var point_size := 24 if primary else 18
		var title_top := 15.0 if primary else 14.0 if subtitle.is_empty() else 6.0
		draw_string(title_font, Vector2(22, title_top + title_font.get_ascent(point_size)), text,
			HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 76, point_size, foreground)
		if not subtitle.is_empty():
			var detail_size := maxi(12 if primary else 11, ceili(11 / drawing_scale))
			var detail_top := 49.0 if primary else 31.0
			draw_string(detail_font, Vector2(23, detail_top + detail_font.get_ascent(detail_size)), subtitle,
				HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 78, detail_size, Color(foreground, 0.76 if primary else 0.85))
		if not disabled and (primary or active):
			var center := Vector2(area.size.x - 29, area.size.y / 2)
			draw_line(center + Vector2(-11, 0), center + Vector2(1, 0), foreground, 1.6, true)
			draw_polyline(PackedVector2Array([center + Vector2(-4, -5), center + Vector2(1, 0), center + Vector2(-4, 5)]), foreground, 1.6, true)
		draw_set_transform(Vector2.ZERO)

var composition := Control.new()
var player_label: Label
var headline: Label
var invitation: Label
var chapter_label: Label
var progress_label: Label
var artwork := TextureRect.new()
var art_caption: Label
var actions: Array[MenuAction] = []
var selection := 0
var lesson_title := "Find the pulse"
var chapter := "Pulse and counts"
var chapter_index := 0
var player := "Player 1"
var unlocked := 1
var cleared := 0
var total := 0
var label_font := make_font(500)
var title_font := make_font(600)
var caption_font: FontVariation
var heading_font: FontVariation

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	composition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(composition)
	player_label = make_label("", label_font, MUTED)
	headline = make_label("Find your\nrhythm.", title_font, PAPER)
	invitation = make_label("Build a rhythm that stays with you.", label_font, MUTED)
	chapter_label = make_label("", label_font, LIME)
	progress_label = make_label("", make_font(400), MUTED)
	art_caption = make_label("LISTEN   /   PLAY   /   REMEMBER", label_font, Color(MUTED, 0.7))
	art_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.clip_text = false
	headline.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading_font = FontVariation.new()
	heading_font.base_font = title_font
	heading_font.spacing_glyph = -3
	headline.add_theme_font_override("font", heading_font)
	caption_font = FontVariation.new()
	caption_font.base_font = label_font
	caption_font.spacing_glyph = 2
	art_caption.add_theme_font_override("font", caption_font)
	artwork.texture = DRUM
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	composition.add_child(artwork)
	composition.move_child(art_caption, -1)
	for index in range(3):
		var action := MenuAction.new()
		action.text = ["Continue", "Learn", "Settings"][index]
		action.primary = index == 0
		action.title_font = make_font(600 if index == 0 else 500)
		action.detail_font = label_font
		action.navigation.connect(move_selection)
		action.focus_entered.connect(func(): select(index))
		action.pressed.connect(func(): activate(index))
		actions.append(action)
		composition.add_child(action)
	for index in range(actions.size()):
		actions[index].focus_neighbor_top = actions[index].get_path_to(actions[posmod(index - 1, actions.size())])
		actions[index].focus_neighbor_bottom = actions[index].get_path_to(actions[(index + 1) % actions.size()])
	resized.connect(layout_menu)
	refresh()
	layout_menu()

func make_label(value: String, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	composition.add_child(label)
	return label

func configure(data: Dictionary) -> void:
	lesson_title = str(data.get("lesson", lesson_title))
	chapter = str(data.get("chapter", chapter))
	chapter_index = int(data.get("chapter_index", chapter_index))
	player = str(data.get("player", player))
	unlocked = int(data.get("unlocked", unlocked))
	cleared = int(data.get("cleared", cleared))
	total = int(data.get("total", total))
	if is_node_ready(): refresh()

func refresh() -> void:
	player_label.text = player.to_upper() + "  /  YOUR PRACTICE"
	chapter_label.text = "CHAPTER %d  /  %s" % [chapter_index + 1, chapter.to_upper()]
	progress_label.text = "%d / %d lessons cleared   ·   %d available" % [cleared, total, unlocked]
	actions[0].subtitle = lesson_title
	actions[0].tooltip_text = "Continue " + lesson_title
	actions[1].subtitle = "Explore foundations · %d lessons" % total
	actions[0].accessibility_description = "Continue " + lesson_title
	actions[1].accessibility_description = "Explore the learning path, including available and upcoming lessons."
	actions[2].accessibility_description = "Connect your kit, adjust sounds, and review local saving."
	for action in actions: action.queue_redraw()
	select(selection)

func layout_menu() -> void:
	if actions.size() != 3 or size.x <= 0 or size.y <= 0:
		return
	var margin := maxf(24, minf(120, size.x * 0.045))
	var usable_width := maxf(1, size.x - margin * 2)
	var usable_height := maxf(1, size.y - 32)
	var scale := minf(1.55, maxf(0.85, minf(usable_width / 920, usable_height / 580)))
	var width := minf(1920, minf(usable_width, maxf(920 * scale, size.x * 0.86)))
	var left_width := 424 * scale
	var art_width := minf(860, minf(width - left_width - 32 * scale, usable_height * 0.91 * 460 / 560))
	var art_height := art_width * 560 / 460
	var height := maxf(580 * scale, art_height)
	composition.position = (size - Vector2(width, height)) / 2
	composition.size = Vector2(width, height)
	var text_top := (height - 580 * scale) / 2
	place(player_label, Rect2(4, 17, 416, 20), scale, text_top)
	place(headline, Rect2(0, 50, 432, 164), scale, text_top)
	place(invitation, Rect2(4, 221, 422, 26), scale, text_top)
	place(chapter_label, Rect2(4, 284, 416, 20), scale, text_top)
	place(actions[0], Rect2(0, 312, 424, 86), scale, text_top)
	place(actions[1], Rect2(0, 407, 424, 54), scale, text_top)
	place(actions[2], Rect2(0, 465, 424, 54), scale, text_top)
	place(progress_label, Rect2(4, 544, 424, 20), scale, text_top)
	artwork.position = Vector2(width - art_width, (height - art_height) / 2)
	artwork.size = Vector2(art_width, art_height)
	var art_scale := art_width / 460
	art_caption.position = artwork.position + Vector2(8, 514) * art_scale
	art_caption.size = Vector2(444, 22) * art_scale
	art_caption.add_theme_font_size_override("font_size", roundi(9 * art_scale))
	caption_font.spacing_glyph = roundi(2 * art_scale)
	player_label.add_theme_font_size_override("font_size", maxi(11, roundi(11 * scale)))
	chapter_label.add_theme_font_size_override("font_size", maxi(11, roundi(10 * scale)))
	progress_label.add_theme_font_size_override("font_size", maxi(11, roundi(11 * scale)))
	invitation.add_theme_font_size_override("font_size", roundi(16 * scale))
	headline.add_theme_font_size_override("font_size", roundi(69 * scale))
	headline.add_theme_constant_override("line_spacing", roundi(-4 * scale))
	heading_font.spacing_glyph = roundi(-2.8 * scale)
	for action in actions:
		action.drawing_scale = scale
		action.queue_redraw()

func place(view: Control, rect: Rect2, scale: float, text_top: float) -> void:
	view.position = rect.position * scale + Vector2(0, text_top)
	view.size = rect.size * scale

func move_selection(offset: int) -> void:
	select(posmod(selection + offset, 3))
	actions[selection].grab_focus()

func select(index: int) -> void:
	selection = index
	for i in range(3):
		actions[i].selected = i == index
		actions[i].queue_redraw()

func activate(index: int) -> void:
	if index < 0 or index >= actions.size() or actions[index].disabled: return
	select(index)
	match index:
		0: continued.emit()
		1: learn_requested.emit()
		2: settings_requested.emit()

func focus_primary() -> void:
	if actions.size() == 3: actions[selection].grab_focus()
