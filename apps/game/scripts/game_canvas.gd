extends Control

const INK = Color("0c1012")
const PAPER = Color("f0f2e8")
const MUTED = Color("92a5a3")
const LIME = Color("cbe880")
const PAD_COLORS = [Color("89cace"), Color("cbe880"), Color("dcb07b")]
var kind := "art"
var events: Array = []
var elapsed := 0.0
var bpm := 60.0
var guidance := 0
var pulses: Array = []
var authored: Array = []
var selected_pad := 1
var checked: Array = []
var current_host := 0.0
var latest := ""
var learn_pad := -1
var font: Font
signal pad_selected(pad: int)

func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP if kind == "kit" else Control.MOUSE_FILTER_IGNORE

func text(value: String, position: Vector2, size_value: int, color: Color = PAPER) -> void:
	draw_string(font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

# One projective plane: both width and depth derive from the same perspective
# factor. The full-width kick uses this exact transform, including its thickness.
func project(lateral: float, beats: float) -> Vector2:
	var strike := size.y * 0.78
	var top := size.y * 0.08
	var far_scale := 1.0 / (1.0 + 0.25 * 8.0)
	var horizon := (top - far_scale * strike) / (1.0 - far_scale)
	var factor := 1.0 / (1.0 + 0.25 * beats)
	return Vector2(size.x / 2.0 + lateral * size.x * 0.42 * factor, horizon + (strike - horizon) * factor)

func tile(left: float, right: float, beats: float, depth: float) -> PackedVector2Array:
	return PackedVector2Array([project(left, beats + depth), project(right, beats + depth), project(right, beats - depth), project(left, beats - depth)])

func lane(pad: int) -> float:
	return -1.0 + (1.5 if pad == 0 else 2.5) * 2.0 / 7.0

func strike_rect(pad: int) -> PackedVector2Array:
	return tile(-0.98, 0.98, 0, 0.075) if pad == 2 else tile(lane(pad) - 0.105, lane(pad) + 0.105, 0, 0.15)

func _draw() -> void:
	if font == null:
		font = ThemeDB.fallback_font
	match kind:
		"art": draw_art()
		"stage": draw_stage()
		"notation": draw_notation()
		"kit": draw_kit()

func draw_art() -> void:
	var scale := minf(size.x / 600.0, size.y / 600.0)
	var center := size / 2.0
	for radius in [250, 220, 190]:
		draw_circle(center, radius * scale, Color(LIME, 0.015))
	for index in range(7):
		var offset := (index - 3) * 60.0 * scale
		draw_line(center + Vector2(offset * 0.2, -280 * scale), center + Vector2(offset * 1.4, 230 * scale), Color(LIME, 0.065), 1.0)
	var ring := PackedVector2Array()
	for index in range(101):
		var angle := float(index) / 100.0 * TAU
		ring.append(center + Vector2(cos(angle) * 245, sin(angle) * 145 + 35) * scale)
	draw_colored_polygon(ring, Color(PAPER, 0.045))
	draw_polyline(ring, Color(LIME, 0.5), 2.0 * scale, true)
	for index in range(7):
		var x := (index - 3) * 58.0 * scale
		var y := sqrt(maxf(0.0, 1.0 - pow(x / (245 * scale), 2))) * 145 * scale + 35 * scale
		draw_line(center + Vector2(x, y), center + Vector2(x, y + 36 * scale), Color(PAPER, 0.16), 4 * scale, true)
	draw_line(center + Vector2(-130, -145) * scale, center + Vector2(115, 150) * scale, Color(PAPER, 0.6), 9 * scale, true)
	draw_line(center + Vector2(165, -195) * scale, center + Vector2(-95, 135) * scale, PAPER, 11 * scale, true)
	text("L I S T E N   /   P L A Y   /   R E M E M B E R", center + Vector2(-195, 260) * scale, int(12 * scale), MUTED)

func draw_stage() -> void:
	# Feather the distant edge with bands on the same world plane.
	for band in range(40):
		var distance := -0.5 + float(band) * 8.5 / 40.0
		var opacity := 0.028 * clampf((8.0 - distance) / 1.5, 0, 1)
		draw_colored_polygon(tile(-1, 1, distance + 8.5 / 80.0, 8.5 / 80.0), Color(PAPER, opacity))
	for index in range(8):
		var lateral := -1.0 + float(index) * 2.0 / 7.0
		for band in range(24):
			var far := 8.0 - float(band) * 8.5 / 24.0
			var near := far - 8.5 / 24.0
			draw_line(project(lateral, far), project(lateral, near), Color(PAPER, 0.09 * clampf((8.0 - near) / 1.5, 0, 1)), 1.0, true)
	var song_beat := elapsed * bpm / 60.0
	for beat in range(floori(song_beat), ceili(song_beat + 8)):
		var depth := float(beat) - song_beat
		if depth >= -0.4:
			draw_line(project(-1, depth), project(1, depth), Color(PAPER, 0.2 if beat % 4 == 0 else 0.06), 1.0, true)
	var show_notes := guidance == 0 or (guidance == 1 and floori(maxf(0.0, song_beat) / 16.0) % 2 == 0)
	if show_notes:
		for event in events:
			var depth := (float(event.time_seconds) - elapsed) * bpm / 60.0
			if depth < -0.35 or depth > 8 or bool(event.get("hit", false)):
				continue
			var pad := int(event.pad)
			var color: Color = Color(PAD_COLORS[pad], clampf((8.0 - depth) / 1.5, 0, 1))
			var polygon := tile(-0.98, 0.98, depth, 0.07) if pad == 2 else tile(lane(pad) - 0.103, lane(pad) + 0.103, depth, 0.14)
			draw_colored_polygon(polygon, color)
			draw_polyline(PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]]), Color(PAPER, 0.26 * color.a), 1.0, true)
	for pad in range(3):
		var polygon := strike_rect(pad)
		draw_polyline(PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]]), PAD_COLORS[pad], 2.0, true)
	for pulse in pulses:
		var age := current_host - float(pulse.host_time)
		if age < 0 or age > 0.42 or int(pulse.pad) < 0:
			continue
		var strength := 1.0 - age / 0.42
		var pad := int(pulse.pad)
		var color: Color = PAD_COLORS[pad]
		if guidance == 0 and int(pulse.get("judgment", 0)) == 4:
			color = Color("e79587")
		draw_colored_polygon(strike_rect(pad), Color(color, strength * 0.85))
		var center := project(0 if pad == 2 else lane(pad), 0)
		draw_arc(center, 15 + age * 80, 0, TAU, 40, Color(color, strength * 0.6), 2.0, true)
	var names := ["CR", "HI-HAT", "SNARE", "T1", "T2", "T3", "RD"]
	for index in range(7):
		var point := project(-1.0 + (float(index) + 0.5) * 2.0 / 7.0, -0.4)
		text(names[index], point + Vector2(-22, 22), 12, PAPER if index in [1, 2] else Color(MUTED, 0.3))
	text("KICK  /  SPACE", Vector2(size.x * 0.71, size.y * 0.91), 12, PAD_COLORS[2])
	if elapsed < 0:
		var count := maxi(1, ceili(-elapsed * bpm / 60.0))
		text(str(count), Vector2(size.x * 0.48, size.y * 0.4), 80, LIME)
	elif not show_notes:
		text("LISTEN TO THE CLICK.  REMEMBER THE PHRASE.", Vector2(size.x * 0.28, size.y * 0.22), 18, MUTED)

func draw_notation() -> void:
	var left := 115.0
	var width := maxf(1, size.x - left - 36)
	var top := 36.0
	var row_height := 40.0
	for pad in range(3):
		text(["HI-HAT", "SNARE", "KICK"][pad], Vector2(4, top + pad * row_height + 6), 12, PAD_COLORS[pad])
		draw_line(Vector2(left, top + pad * row_height), Vector2(left + width, top + pad * row_height), Color(PAPER, 0.13), 1.0)
	for index in range(8):
		var x := left + float(index) / 8 * width
		text(str(floori(index / 2.0) + 1) if index % 2 == 0 else "&", Vector2(x - 4, top + 124), 16, MUTED)
		if index % 2 == 0:
			draw_line(Vector2(x, 10), Vector2(x, top + 96), Color(PAPER, 0.045), 1.0)
	for event in authored:
		var pad := int(event.pad)
		var center := Vector2(left + float(event.beat) / 4 * width, top + pad * row_height)
		if pad == 0:
			draw_line(center - Vector2(6, 6), center + Vector2(6, 6), PAD_COLORS[pad], 2, true)
			draw_line(center + Vector2(-6, 6), center + Vector2(6, -6), PAD_COLORS[pad], 2, true)
		else:
			draw_circle(center, 6, PAD_COLORS[pad])
		if event.get("hand", "") != "":
			text(event.hand, center + Vector2(-4, -11), 10, MUTED)

func kit_center(pad: int) -> Vector2:
	return [Vector2(size.x * 0.24, size.y * 0.34), Vector2(size.x * 0.69, size.y * 0.43), Vector2(size.x * 0.46, size.y * 0.74)][pad]

func draw_kit() -> void:
	var radius := minf(size.x * 0.19, size.y * 0.19)
	for pad in range(3):
		var center := kit_center(pad)
		var color: Color = PAD_COLORS[pad]
		var active := false
		for hit in pulses:
			if int(hit.pad) == pad and current_host - float(hit.host_time) < 0.22:
				active = true
		draw_circle(center, radius, Color(color, 0.22 if active else 0.06))
		draw_arc(center, radius, 0, TAU, 80, color if pad == selected_pad or active else Color(color, 0.3), 2, true)
		draw_arc(center, radius * 0.85, 0, TAU, 80, Color(color, 0.13), 1, true)
		text(["HI-HAT", "SNARE", "KICK"][pad], center + Vector2(-26, 3), 13, color)
		text("STRIKE TO MAP" if learn_pad == pad else "INPUT RECEIVED" if pad in checked else "STRIKE TO CHECK", center + Vector2(-55, radius + 23), 10, MUTED)

func _gui_input(event: InputEvent) -> void:
	if kind == "kit" and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for pad in range(3):
			if event.position.distance_to(kit_center(pad)) <= minf(size.x * 0.19, size.y * 0.19):
				pad_selected.emit(pad)
				accept_event()
