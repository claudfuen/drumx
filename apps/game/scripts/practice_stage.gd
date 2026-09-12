extends Control
## Faithful translation of native/macos/PracticeView.swift and DrumxProjection.swift.
## All measurements are logical UI points. Window/backing-pixel scaling belongs to
## the application shell, never this projection or individual note geometry.

const BACKGROUND = Color(0.055, 0.076, 0.082, 1)
const FAR = Color(0.078, 0.112, 0.121, 1)
const NEAR = Color(0.120, 0.178, 0.186, 1)
const INK = Color(0.921, 0.938, 0.900, 1)
const MUTED = Color(0.574, 0.649, 0.645, 1)
const QUIET = Color(0.280, 0.351, 0.351, 1)
const LINE = Color(0.240, 0.315, 0.320, 1)
const HAT = Color(0.540, 0.792, 0.808, 1)
const SNARE = Color(0.807, 0.917, 0.578, 1)
const KICK = Color(0.865, 0.683, 0.442, 1)
const MEMORY = Color(0.694, 0.614, 0.798, 1)
const EXTRA = Color(0.940, 0.451, 0.395, 1)
const PAD_COLORS = [HAT, SNARE, KICK]
const PREVIEW_BEATS = 4.0
const FAR_SCALE = 0.42
const DEPTH_SLOPE = (1.0 / FAR_SCALE - 1.0) / PREVIEW_BEATS
const HIT_DURATION = 0.42

# Existing shared stage contract.
var events: Array = []
var elapsed := 0.0
var bpm := 60.0
var guidance := 0
var pulses: Array = []
var current_host := 0.0
# Original renderer state supplied by the shell. This view never scores input.
var lesson_title := "Practice"
var lesson_bars := 16
var authored: Array = []
var show_hands := true
var show_live := true
var active := true
var completed := false
var demonstrating := false
var reduce_motion := false
var bias: Array = []

var font: Font
var regular_font: Font
var semibold_font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ensure_fonts()

func ensure_fonts() -> void:
	if font != null:
		return
	for weight in [500, 400, 600]:
		var face := SystemFont.new()
		face.font_names = PackedStringArray([".AppleSystemUIFont", "SF Pro Text", "Segoe UI", "Helvetica Neue"])
		face.font_weight = weight
		face.allow_system_fallback = true
		if weight == 500: font = face
		elif weight == 400: regular_font = face
		else: semibold_font = face

func caption(value: String, x: float, y: float, font_size: int = 11,
		color: Color = MUTED, alignment: int = HORIZONTAL_ALIGNMENT_LEFT,
		weight: int = 500) -> void:
	var face: Font = regular_font if weight == 400 else semibold_font if weight == 600 else font
	var width := face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var origin := x - width / 2.0 if alignment == HORIZONTAL_ALIGNMENT_CENTER else x - width if alignment == HORIZONTAL_ALIGNMENT_RIGHT else x
	draw_string(face, Vector2(origin, y + face.get_ascent(font_size)), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func top_y() -> float: return 55.0
func strike_y() -> float: return maxf(top_y() + 160.0, size.y - 193.0)
func near_width() -> float: return minf(870.0, size.x - 132.0)

func project(lateral: float, beat_distance: float) -> Vector2:
	var horizon := (top_y() - FAR_SCALE * strike_y()) / (1.0 - FAR_SCALE)
	var factor := 1.0 / (1.0 + DEPTH_SLOPE * beat_distance)
	return Vector2(size.x / 2.0 + near_width() * lateral * factor,
		horizon + (strike_y() - horizon) * factor)

func lane_center(slot: int) -> float: return -0.5 + (float(slot) + 0.5) / 7.0

func far_visibility(distance: float) -> float:
	var value := clampf((PREVIEW_BEATS - distance) / 0.7, 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)

func rectangle(center: float, distance: float, width: float, depth: float) -> PackedVector2Array:
	return PackedVector2Array([
		project(center - width / 2, distance + depth / 2),
		project(center + width / 2, distance + depth / 2),
		project(center + width / 2, distance - depth / 2),
		project(center - width / 2, distance - depth / 2)])

func cymbal(center: float, distance: float, width: float, depth: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in [Vector2(-width / 2, 0), Vector2(-width * 0.29, depth / 2),
		Vector2(width * 0.29, depth / 2), Vector2(width / 2, 0),
		Vector2(width * 0.29, -depth / 2), Vector2(-width * 0.29, -depth / 2)]:
		result.append(project(center + point.x, distance + point.y))
	return result

func drum(center: float, distance: float, width: float, depth: float) -> PackedVector2Array:
	var rx := width * 0.17
	var rz := depth * 0.27
	var result := PackedVector2Array()
	for corner in [Vector3(width / 2 - rx, depth / 2 - rz, 0),
		Vector3(-width / 2 + rx, depth / 2 - rz, PI / 2),
		Vector3(-width / 2 + rx, -depth / 2 + rz, PI),
		Vector3(width / 2 - rx, -depth / 2 + rz, PI * 1.5)]:
		for step in range(5):
			var angle: float = corner.z + float(step) * PI / 8
			result.append(project(center + corner.x + cos(angle) * rx,
				distance + corner.y + sin(angle) * rz))
	return result

func note_vertices(pad: int, beat_distance: float) -> PackedVector2Array:
	if pad == 2: return rectangle(0, beat_distance, 0.99, 0.04)
	var lateral := lane_center(0 if pad == 0 else 2)
	return cymbal(lateral, beat_distance, 0.66 / 7, 0.12) if pad == 0 else drum(lateral, beat_distance, 0.66 / 7, 0.12)

func outline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2: return
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func oval(center: Vector2, radii: Vector2, color: Color, width: float = 0) -> void:
	var points := PackedVector2Array()
	for step in range(49):
		var angle := float(step) * TAU / 48
		points.append(center + Vector2(cos(angle), sin(angle)) * radii)
	if width > 0: draw_polyline(points, color, width, true)
	else: draw_colored_polygon(points, color)

func soft_shadow(points: PackedVector2Array, color: Color, blur: float, offset: Vector2 = Vector2.ZERO) -> void:
	# Layered antialiased strokes implement the same local soft-edge treatment as
	# AppKit's NSShadow. They never change the note's projected silhouette.
	var shape := PackedVector2Array()
	for point in points: shape.append(point + offset)
	for layer in range(6, 0, -1):
		var fraction := float(layer) / 6
		outline(shape, Color(color, color.a * (1.0 - fraction * 0.7) / 6), blur * fraction * 2)
	draw_colored_polygon(shape, Color(color, color.a * 0.35))

func road_surface(far_distance: float, near_distance: float) -> PackedVector2Array:
	return PackedVector2Array([project(-0.5, far_distance), project(0.5, far_distance),
		project(0.5, near_distance), project(-0.5, near_distance)])

func catcher_path(slot: int, scale_x: float = 1.0, scale_y: float = 1.0) -> PackedVector2Array:
	var lateral := 0.0 if slot == 7 else lane_center(slot)
	var center := project(lateral, 0)
	var shape: PackedVector2Array
	if slot == 7: shape = rectangle(0, 0, 0.99, 0.065)
	elif slot in [0, 1, 6]: shape = cymbal(lateral, 0, 0.75 / 7, 0.16)
	else: shape = drum(lateral, 0, 0.75 / 7, 0.16)
	for index in range(shape.size()):
		shape[index] = center + (shape[index] - center) * Vector2(scale_x, scale_y)
	return shape

func visible_hits() -> Array:
	var result: Array = []
	for pulse in pulses:
		var age := current_host - float(pulse.get("host_time", 0))
		if int(pulse.get("pad", -1)) not in [0, 1, 2] or age < 0 or age >= HIT_DURATION:
			continue
		var item: Dictionary = pulse.duplicate()
		item.age = age
		item.strength = 0.65 + clampf(float(pulse.get("velocity", 100)) / 127.0, 0, 1) * 0.35
		result.append(item)
	return result

func hit_kind(hit: Dictionary, reveal: bool) -> int:
	if not reveal: return 0
	var judgment := int(hit.get("judgment", 0))
	return 1 if judgment in [1, 2, 3] else 2 if judgment == 4 else 0

func draw_catchers(slots: Array, hits: Array) -> void:
	for slot in slots:
		var pad := 0 if slot == 0 else 1 if slot == 2 else 2 if slot == 7 else -1
		var used := pad >= 0
		var color: Color = PAD_COLORS[pad] if used else QUIET
		var shape := catcher_path(slot)
		draw_colored_polygon(shape, Color(BACKGROUND, 0.9))
		outline(shape, Color(color, 0.65 if used else 0.47), 1.5 if used else 1.0)
		var newest: Dictionary = {}
		for hit in hits:
			if int(hit.pad) == pad: newest = hit
		if not used or newest.is_empty(): continue
		var age := float(newest.age)
		var envelope := maxf(0, 1.0 - age / 0.27)
		if envelope <= 0: continue
		var strength := envelope * float(newest.strength)
		var scale_x := 1.0
		var scale_y := 1.0
		if not reduce_motion:
			var compression := maxf(0, 1.0 - age / 0.07)
			var rebound := maxf(0, 1.0 - absf(age - 0.105) / 0.075)
			scale_x += 0.035 * rebound - 0.015 * compression
			scale_y += 0.10 * rebound - 0.18 * compression
		var response := catcher_path(slot, scale_x, scale_y)
		soft_shadow(response, Color(color, 0.48 * strength), 6 if reduce_motion else 11)
		draw_colored_polygon(response, Color(color, 0.25 * strength))
		outline(response, Color(color, 0.94 * strength), 1.8)

func draw_hit_bursts(pads: Array, hits: Array, reveal: bool) -> void:
	if not reveal: return
	for hit in hits:
		var pad := int(hit.pad)
		var kind := hit_kind(hit, reveal)
		var progress := float(hit.age) / 0.30
		if pad not in pads or kind == 0 or progress >= 1: continue
		var center := project(0 if pad == 2 else lane_center(0 if pad == 0 else 2), 0)
		var alpha := (1.0 - progress) * float(hit.strength)
		var color: Color = EXTRA if kind == 2 else PAD_COLORS[pad]
		if pad == 2:
			outline(catcher_path(7), Color(color, 0.78 * alpha), 2.2)
			if not reduce_motion:
				for side in [-1.0, 1.0]:
					var edge: float = center.x + side * near_width() * 0.505
					var rise := 7.0 + 22 * progress
					if kind == 1:
						draw_line(Vector2(edge, center.y - 4), Vector2(edge + side * 4 * progress, center.y - rise), Color(color, alpha), 2, true)
					else:
						draw_colored_polygon(PackedVector2Array([
							Vector2(edge + side * 6 * progress, center.y - rise),
							Vector2(edge + side * (6 + 9 * progress), center.y - rise + 5),
							Vector2(edge + side * (2 + 6 * progress), center.y - rise + 10)]), Color(color, alpha))
			continue
		if reduce_motion:
			outline(catcher_path(0 if pad == 0 else 2), Color(color, 0.70 * alpha), 2)
		elif kind == 1:
			oval(center, Vector2(42 + 35 * progress, 10 + 11 * progress) / 2, Color(color, 0.46 * alpha), 1.25)
			for side in [-1, 0, 1]:
				var dx: float = side * (11 + 17 * progress)
				var rise := 9 + 28 * progress
				draw_line(center + Vector2(dx * 0.80, -rise + 5), center + Vector2(dx, -rise - 2), Color(color, 0.80 * alpha), 1.6, true)
		else:
			var half_width := near_width() * 0.40 / 7
			for side in [-1.0, 1.0]:
				var dx := half_width + 5 + 13 * progress
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(side * dx, -5 - 7 * progress),
					center + Vector2(side * (dx + 5), -1 - 7 * progress),
					center + Vector2(side * (dx + 2), 3 - 7 * progress)]), Color(color, 0.90 * alpha))

func hand_hint(pad: int, time_seconds: float) -> String:
	var beat := fposmod(time_seconds * bpm / 60.0, 4.0)
	for event in authored:
		if int(event.pad) == pad and absf(float(event.beat) - beat) < 0.00001:
			return str(event.get("hand", ""))
	return ""

func _draw() -> void:
	ensure_fonts()
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if size.x <= 200 or size.y <= 260: return
	var beat := elapsed * bpm / 60.0
	var count_in := active and elapsed < 0
	var strict_memory := guidance == 2 and not demonstrating
	var fade := guidance == 1 and not demonstrating
	var reveal := show_live and not demonstrating
	var in_memory_bar := active and not count_in and not demonstrating and (strict_memory or (fade and int(beat / 4) % 2 == 1))
	var center := size.x / 2.0
	var top := top_y()
	var strike := strike_y()
	var width := near_width()
	var hits := visible_hits()
	var title := "Listen to the groove" if demonstrating else "Settle into the click" if count_in else "From memory" if in_memory_bar else "Take complete" if completed else lesson_title
	caption(title, 28, 15, 15, INK)
	var mode: String = "Demonstration" if demonstrating else ["Guided", "Hidden bars", "From memory"][clampi(guidance, 0, 2)]
	caption("%d BPM  ·  %s" % [int(bpm), mode], size.x - 28, 18, 11, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	var road := road_surface(PREVIEW_BEATS, 0)
	soft_shadow(road, Color(Color.BLACK, 0.16), 18, Vector2(0, 7))
	draw_polygon(road, PackedColorArray([FAR, FAR, NEAR, NEAR]))
	for slot in [1, 3, 4, 5, 6]:
		var left := -0.5 + float(slot) / 7
		var right := -0.5 + float(slot + 1) / 7
		draw_colored_polygon(PackedVector2Array([project(left, 4), project(right, 4), project(right, 0), project(left, 0)]), Color(BACKGROUND, 0.33))
	if strict_memory:
		draw_colored_polygon(road, Color(MEMORY, 0.075))
	elif fade:
		for bar in range(1, maxi(1, lesson_bars), 2):
			var near := maxf(0, bar * 4.0 - beat)
			var far := minf(4, bar * 4.0 + 4 - beat)
			if far <= near or near >= 4 or far <= 0: continue
			draw_colored_polygon(road_surface(far, near), Color(MEMORY, 0.115))
			var far_y := project(0, far).y
			var near_y := project(0, near).y
			if near_y - far_y > 40:
				caption("FROM MEMORY", center, (near_y + far_y) / 2 - 7, 11, MEMORY, HORIZONTAL_ALIGNMENT_CENTER)
	for slot in range(8):
		var lateral := -0.5 + float(slot) / 7
		var edge := slot in [0, 7]
		draw_line(project(lateral, 4), project(lateral, 0), Color(LINE, 0.72 if edge else 0.44), 1 if edge else 0.7, true)
	if not strict_memory:
		for index in range(maxi(1, lesson_bars) * 4 + 1):
			var ahead := float(index) - beat
			if ahead < 0 or ahead > 4: continue
			var left := project(-0.5, ahead)
			var right := project(0.5, ahead)
			draw_line(left, right, Color(LINE, 0.82 if index % 4 == 0 else 0.51), 1.25 if index % 4 == 0 else 0.65, true)
			if index < lesson_bars * 4:
				caption(str(index % 4 + 1), left.x - 17, left.y - 7, 11, Color(MUTED, 0.76), HORIZONTAL_ALIGNMENT_CENTER)
	elif not count_in:
		caption("FROM MEMORY", center, top + (strike - top) * 0.44, 13, MEMORY, HORIZONTAL_ALIGNMENT_CENTER)
	draw_colored_polygon(PackedVector2Array([Vector2(center - width / 2, strike), Vector2(center + width / 2, strike),
		Vector2(center + width / 2 - 8, strike + 7), Vector2(center - width / 2 + 8, strike + 7)]), Color(LINE, 0.48))
	draw_line(Vector2(center - width / 2, strike), Vector2(center + width / 2, strike), Color(INK, 0.78), 1.5, true)
	caption("NOW", center - width / 2 - 32, strike - 7, 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	# Identical native layer order: complete foot layer, then all hand layers.
	draw_catchers([7], hits)
	for render_pad in [2, 0, 1]:
		if render_pad == 0:
			draw_hit_bursts([2], hits, reveal)
			draw_catchers([0, 1, 2, 3, 4, 5, 6], hits)
		if strict_memory: continue
		for event in events:
			if int(event.pad) != render_pad or (reveal and bool(event.get("hit", false))): continue
			var ahead_seconds := float(event.time_seconds) - elapsed
			if ahead_seconds < -0.015 or ahead_seconds > 4 * 60 / bpm: continue
			if fade and int((float(event.time_seconds) * bpm / 60 + 0.000001) / 4) % 2 == 1: continue
			var distance := ahead_seconds * bpm / 60
			var lateral := 0.0 if render_pad == 2 else lane_center(0 if render_pad == 0 else 2)
			var point := project(lateral, distance)
			var alpha := far_visibility(distance)
			var color: Color = Color(PAD_COLORS[render_pad], alpha)
			if render_pad == 2:
				draw_colored_polygon(rectangle(0, distance, 0.99, 0.04), color)
			else:
				var shape := cymbal(lateral, distance, 0.66 / 7, 0.12) if render_pad == 0 else drum(lateral, distance, 0.66 / 7, 0.12)
				soft_shadow(shape, Color(Color.BLACK, 0.18 * alpha), 3, Vector2(0, 2))
				draw_colored_polygon(shape, color)
				if render_pad == 0 and not show_hands:
					draw_line(project(lateral - 0.022, distance + 0.015), project(lateral + 0.022, distance + 0.015), Color(BACKGROUND, 0.25 * alpha), 1, true)
				if show_hands:
					var box := Rect2(shape[0], Vector2.ZERO)
					for vertex in shape: box = box.expand(vertex)
					var hand := hand_hint(render_pad, float(event.time_seconds))
					if box.size.x >= 24 and box.size.y >= 13 and hand != "":
						caption(hand, point.x, point.y - 7, 11, Color(BACKGROUND, alpha), HORIZONTAL_ALIGNMENT_CENTER)
	draw_hit_bursts([0, 1], hits, reveal)
	# One atmospheric mask covers road, lanes, grid and notes together.
	var feather_height := maxf(38, (strike - top) * 0.18)
	draw_rect(Rect2(0, top - 14, size.x, 14), BACKGROUND)
	draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, top + feather_height), Vector2(0, top + feather_height)]),
		PackedColorArray([BACKGROUND, BACKGROUND, Color(BACKGROUND, 0), Color(BACKGROUND, 0)]))
	draw_kit_references(hits, reveal)
	if count_in:
		var count := clampi(floori(4 + elapsed * bpm / 60) + 1, 1, 4)
		caption(str(count), center, top + (strike - top) * 0.32 - 20, 68, INK, HORIZONTAL_ALIGNMENT_CENTER, 400)
	if demonstrating:
		caption("LISTEN · DEMONSTRATION IS NOT SCORED", center, strike + 139, 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	elif show_live or not active:
		draw_timing(center, strike + 112)
	else:
		caption("Timing feedback after the phrase", center, strike + 139, 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)

func draw_kit_references(hits: Array, reveal: bool) -> void:
	var strike := strike_y()
	var center := size.x / 2
	var width := near_width()
	var names := ["HI-HAT", "CRASH", "SNARE", "TOM 1", "TOM 2", "FLOOR", "RIDE"]
	for slot in range(7):
		var is_cymbal := slot in [0, 1, 6]
		var used := slot in [0, 2]
		var color: Color = (HAT if slot == 0 else SNARE) if used else QUIET
		var x := project(lane_center(slot), 0).x
		var cy := strike + (29 if is_cymbal else 43)
		var radius := minf(29, width / 7 * 0.29)
		var ry := 4.5 if is_cymbal else 10.0
		draw_line(Vector2(x, strike + 9), Vector2(x, cy - ry - 3), Color(LINE, 0.75 if used else 0.36), 0.8, true)
		oval(Vector2(x, cy), Vector2(radius, ry), BACKGROUND)
		oval(Vector2(x, cy), Vector2(radius, ry), Color(color, 0.78 if used else 0.62), 1.1)
		if is_cymbal: oval(Vector2(x, cy), Vector2(3.5, 1.4), Color(color, 0.6))
		else: oval(Vector2(x, cy), Vector2(radius - 4, ry - 3), Color(color, 0.22), 1)
		caption(names[slot], x, cy + ry + 8, 11, INK if used else Color(MUTED, 0.78), HORIZONTAL_ALIGNMENT_CENTER)
	draw_style_box(foot_underline(), Rect2(center - width * 0.20, strike + 76, width * 0.40, 2))
	var extra_kick := false
	for hit in hits:
		if int(hit.pad) == 2 and hit_kind(hit, reveal) == 2: extra_kick = true
	caption("KICK · EXTRA" if extra_kick else "KICK · FOOT", center, strike + 82, 11, EXTRA if extra_kick else KICK, HORIZONTAL_ALIGNMENT_CENTER)
	if not reveal: return
	for pad in range(2):
		var newest: Dictionary = {}
		for hit in hits:
			if int(hit.pad) == pad and hit_kind(hit, reveal) == 2: newest = hit
		if newest.is_empty(): continue
		var alpha := minf(1, (1 - float(newest.age) / HIT_DURATION) * 2)
		var point := project(lane_center(0 if pad == 0 else 2), 0) + Vector2(0, 12)
		draw_rect(Rect2(point.x - 23, point.y, 46, 14), Color(BACKGROUND, 0.96 * alpha))
		caption("EXTRA", point.x, point.y, 11, Color(EXTRA, alpha), HORIZONTAL_ALIGNMENT_CENTER, 600)

func foot_underline() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(KICK, 0.36)
	box.set_corner_radius_all(1)
	return box

func draw_timing(center: float, top: float) -> void:
	var left := center - 132
	var right := center + 132
	caption("EARLY", left, top)
	caption("ON TIME", center, top, 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	caption("LATE", right, top, 11, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	for pad in range(3):
		var item: Dictionary = bias[pad] if pad < bias.size() else {"state": 0, "sample_count": 0, "offset_ms": 0}
		var row := top + 25 + pad * 20
		caption(["Hi-hat", "Snare", "Kick"][pad], left - 20, row - 7, 11, PAD_COLORS[pad], HORIZONTAL_ALIGNMENT_RIGHT)
		draw_line(Vector2(left, row), Vector2(right, row), Color(LINE, 0.65), 0.7, true)
		draw_line(Vector2(center, row - 4), Vector2(center, row + 4), Color(MUTED, 0.5), 0.8, true)
		var count := int(item.get("sample_count", 0))
		var state := int(item.get("state", 0))
		var offset := float(item.get("offset_ms", 0))
		if count >= 4 and state != 5:
			draw_circle(Vector2(center + clampf(offset, -80, 80) / 80 * 132, row), 3, PAD_COLORS[pad])
		var value := "%d/4 hits" % count if state == 0 else "Uneven timing" if state == 4 else "Waiting for hits" if state == 5 else "%+.0f ms" % offset
		caption(value, right + 18, row - 7)
