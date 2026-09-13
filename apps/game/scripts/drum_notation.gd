extends Control

# Direct port of native/macos/DrumxNotationView.swift. This one-bar view uses
# the same quarter/eighth spelling and original logical-point geometry.
const MenuFonts = preload("res://scripts/main_menu.gd")
const BACKGROUND = Color(0.055, 0.076, 0.082, 1)
const INK = Color(0.921, 0.938, 0.900, 1)
const MUTED = Color(0.574, 0.649, 0.645, 1)
const PAD_NAMES = ["Hi-hat", "Snare", "Kick"]

var authored: Array = []:
	set(value):
		authored = value.duplicate(true)
		refresh_notation()
var lesson_title: String = "":
	set(value):
		lesson_title = value
		refresh_notation()
var notation: Dictionary = {}
var notation_font: Font = MenuFonts.make_font(500)

class InkPath extends RefCounted:
	var points := PackedVector2Array()
	var origin := Vector2.ZERO
	var direction := 1.0
	func _init(at: Vector2, sign_value: float = 1.0) -> void:
		origin = at
		direction = sign_value
	func point(x: float, y: float) -> Vector2:
		return origin + Vector2(x, y) * direction
	func line(x: float, y: float) -> void:
		points.append(point(x, y))
	func curve(c1x: float, c1y: float, c2x: float, c2y: float, end_x: float, end_y: float) -> void:
		var start := points[points.size() - 1]
		var first := point(c1x, c1y)
		var second := point(c2x, c2y)
		var end := point(end_x, end_y)
		# Sample the original cubic paths, keeping their control points intact.
		for index in range(1, 21):
			points.append(start.bezier_interpolate(first, second, end, float(index) / 20.0))

func _init() -> void:
	custom_minimum_size = Vector2(320, 172)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	refresh_notation()

func _ready() -> void:
	resized.connect(queue_redraw)
	refresh_notation()

static func notation_model(events: Array) -> Dictionary:
	var groups: Array = [[], [], [], [], [], [], [], []]
	var sticking: Array = [[], [], [], [], [], [], [], []]
	var pads: Array = []
	var eighths := false
	var keys := {}
	for event in events:
		if not event is Dictionary:
			return {"valid": false}
		var beat_value = event.get("beat")
		var pad_value = event.get("pad")
		if typeof(beat_value) not in [TYPE_INT, TYPE_FLOAT] or typeof(pad_value) not in [TYPE_INT, TYPE_FLOAT]:
			return {"valid": false}
		var beat := float(beat_value)
		var pad_number := float(pad_value)
		if not is_finite(beat) or beat < 0 or beat >= 4 or not is_finite(pad_number) or pad_number != floorf(pad_number) or pad_number < 0 or pad_number >= 3:
			return {"valid": false}
		if absf(beat * 2 - roundf(beat * 2)) >= 0.000001:
			return {"valid": false}
		var tick := roundi(beat * 2)
		if tick < 0 or tick >= 8:
			return {"valid": false}
		var pad := int(pad_number)
		var key := tick * 3 + pad
		if keys.has(key):
			return {"valid": false}
		keys[key] = true
		groups[tick].append(pad)
		var hand = event.get("hand")
		if pad != 2 and hand in ["R", "L"] and not sticking[tick].has(hand):
			sticking[tick].append(hand)
		if not pads.has(pad):
			pads.append(pad)
		eighths = eighths or tick % 2 == 1
	for group in groups:
		group.sort()
	for hands in sticking:
		hands.sort()
	pads.sort()
	var upper_present := pads.has(0) or pads.has(1)
	var lower_present := pads.has(2)
	var voices: Array = []
	# An absent part stays absent. An entirely empty bar has one rest voice.
	for down in [false, true]:
		if down and not lower_present:
			continue
		if not down and not upper_present and lower_present:
			continue
		var beats: Array = []
		for beat in range(4):
			var first: Array = []
			var second: Array = []
			for pad in groups[beat * 2]:
				if (pad == 2) == down:
					first.append(pad)
			for pad in groups[beat * 2 + 1]:
				if (pad == 2) == down:
					second.append(pad)
			var kind := "quarter_rest"
			if not first.is_empty() and second.is_empty():
				kind = "quarter"
			elif first.is_empty() and not second.is_empty():
				kind = "eighth_rest_note"
			elif not first.is_empty() and not second.is_empty():
				kind = "eighth_pair"
			beats.append({"kind": kind, "first": first, "second": second})
		voices.append({"down": down, "beats": beats})
	var counts: Array = []
	for tick in range(0, 8, 1 if eighths else 2):
		counts.append({"tick": tick, "text": str(tick / 2 + 1) if tick % 2 == 0 else "&", "pads": groups[tick]})
	return {"valid": true, "groups": groups, "pads": pads, "eighths": eighths,
		"upper_present": upper_present, "lower_present": lower_present, "voices": voices, "counts": counts, "sticking": sticking}

func refresh_notation() -> void:
	notation = notation_model(authored)
	if lesson_title.is_empty():
		accessibility_name = "One-bar drum notation. Choose a lesson to read its rhythm."
	elif not notation.valid:
		accessibility_name = lesson_title + ". Notation is unavailable for this rhythm."
	else:
		var descriptions := PackedStringArray()
		for count in notation.counts:
			var tick := int(count.tick)
			var label := "Count %d" % (tick / 2 + 1) if tick % 2 == 0 else "And of %d" % (tick / 2 + 1)
			var instruments := PackedStringArray()
			for pad in count.pads:
				instruments.append(PAD_NAMES[pad])
			var hands: Array = notation.sticking[tick]
			var suggestion := "" if hands.is_empty() else "; suggested hands " + " and ".join(hands)
			descriptions.append(label + ": " + ("no strike" if instruments.is_empty() else " and ".join(instruments)) + suggestion)
		accessibility_name = lesson_title + ". One bar of four-four time. " + ". ".join(descriptions) + ". Hi-hat and snare share the upper voice; kick uses the lower voice when present."
	queue_redraw()

func text(value: String, x: float, y: float, point_size: int = 11, color: Color = MUTED, centered: bool = false) -> void:
	var width := notation_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x
	draw_string(notation_font, Vector2(x - width / 2 if centered else x, y + notation_font.get_ascent(point_size)),
		value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, color)

func line(x1: float, y1: float, x2: float, y2: float, color: Color = INK, width: float = 1.1) -> void:
	draw_line(Vector2(x1, y1), Vector2(x2, y2), color, width, true)

func ellipse(center: Vector2, radii: Vector2, angle: float = 0.0) -> void:
	var points := PackedVector2Array()
	for index in range(48):
		var phase := TAU * float(index) / 48.0
		points.append(center + Vector2(cos(phase) * radii.x, sin(phase) * radii.y).rotated(angle))
	draw_colored_polygon(points, INK)

func notehead(x: float, y: float, cross: bool = false) -> void:
	if cross:
		line(x - 4, y - 3.5, x + 4, y + 3.5, INK, 1.5)
		line(x - 4, y + 3.5, x + 4, y - 3.5, INK, 1.5)
	else:
		ellipse(Vector2(x, y), Vector2(5.5, 3.5), deg_to_rad(-17))

func quarter_rest(x: float, y: float) -> void:
	var path := InkPath.new(Vector2(x, y))
	path.line(1, -17)
	path.line(7, -9)
	path.line(2, -3)
	path.line(7, 4)
	path.curve(1, 1, -4, 2, -4, 6)
	path.curve(-4, 10, -1, 13, 1, 16)
	path.curve(-4, 13, -8, 9, -8, 5)
	path.curve(-8, 1, -4, -2, -1, -1)
	path.line(-5, -7)
	path.line(1, -13)
	path.line(-2, -18)
	draw_colored_polygon(path.points, INK)

func eighth_rest(x: float, y: float) -> void:
	var path := InkPath.new(Vector2(x, y))
	path.line(-4, 12)
	path.line(4, -11)
	path.curve(1, -5, -3, -3, -5, -6)
	draw_polyline(path.points, INK, 1.7, true)
	ellipse(Vector2(x - 5, y - 6), Vector2(3, 3))

func eighth_flag(stem_x: float, end_y: float, down: bool) -> void:
	var path := InkPath.new(Vector2(stem_x, end_y), -1.0 if down else 1.0)
	path.line(0, 0)
	path.curve(2, 6, 10, 7, 10, 11)
	path.curve(12, 16, 8, 22, 5, 24)
	path.curve(9, 17, 9, 14, 6, 12)
	path.curve(1, 11, 1, 9, 0, 7)
	draw_colored_polygon(path.points, INK)

func chord(pads: Array, x: float, ys: Array, end_y: float, down: bool, flagged: bool) -> void:
	var start_y: float = ys[pads[0]]
	for pad in pads:
		notehead(x, ys[pad], pad == 0)
		start_y = minf(start_y, ys[pad]) if down else maxf(start_y, ys[pad])
	var stem_x := x + (-5.0 if down else 4.5)
	line(stem_x, start_y, stem_x, end_y)
	if flagged:
		eighth_flag(stem_x, end_y, down)

func draw_voice(voice: Dictionary, staff_top: float, note_start: float, step: float, rest_y: float) -> void:
	var down: bool = voice.down
	var ys: Array = [staff_top - 5, staff_top + 15, staff_top + 35]
	for beat in range(4):
		var plan: Dictionary = voice.beats[beat]
		var first: Array = plan.first
		var second: Array = plan.second
		var x := note_start + float(beat * 2) * step
		if plan.kind == "quarter_rest":
			quarter_rest(x, rest_y)
			continue
		var notes: Array = first + second
		var top: float = ys[notes[0]]
		for pad in notes:
			top = minf(top, ys[pad])
		var end_y: float = ys[2] + 31 if down else top - 30
		if plan.kind == "quarter":
			chord(first, x, ys, end_y, down, false)
		elif plan.kind == "eighth_rest_note":
			eighth_rest(x, rest_y)
			chord(second, x + step, ys, end_y, down, true)
		else:
			chord(first, x, ys, end_y, down, false)
			chord(second, x + step, ys, end_y, down, false)
			draw_rect(Rect2(x + (-5.0 if down else 4.5), end_y - (3.6 if down else 0.0), step + 0.5, 3.6), INK)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if size.x < 320 or size.y < 168:
		text("Enlarge this view to read the bar.", 16, 12)
		return
	if lesson_title.is_empty() or not notation.get("valid", false):
		text("Choose a lesson to read its rhythm." if lesson_title.is_empty() else "Notation is unavailable for this rhythm.", 24, 24)
		return
	var offset := maxf(0, (size.y - 172) / 2)
	var left := 24.0
	var right := size.x - 24
	var staff_top := offset + 54
	var note_start := 114.0
	var step := (right - note_start - 18) / 8
	text("ONE BAR / 4/4", left, offset + 6)
	for row in range(5):
		var y := staff_top + float(row) * 10
		line(left, y, right, y, Color(MUTED, 0.55), 0.65)
	line(left, staff_top, left, staff_top + 40, Color(MUTED, 0.65), 0.8)
	line(right - 4, staff_top, right - 4, staff_top + 40, INK, 0.8)
	line(right, staff_top, right, staff_top + 40, INK, 2)
	draw_rect(Rect2(left + 13, staff_top + 8, 3, 24), INK)
	draw_rect(Rect2(left + 21, staff_top + 8, 3, 24), INK)
	text("4", left + 51, staff_top - 4, 22, INK, true)
	text("4", left + 51, staff_top + 17, 22, INK, true)
	for voice in notation.voices:
		var rest_y := staff_top + (20 if not notation.upper_present else 52) if voice.down else staff_top + (20 if not notation.lower_present else 9)
		draw_voice(voice, staff_top, note_start, step, rest_y)
	for count in notation.counts:
		var tick := int(count.tick)
		text(count.text, note_start + float(tick) * step, offset + 132, 12, INK if tick % 2 == 0 else MUTED, true)
	var key_width := 57.0 if size.x < 540 else 88.0
	var key_start := right - float(notation.pads.size()) * key_width
	for index in range(notation.pads.size()):
		var pad: int = notation.pads[index]
		var x := key_start + float(index) * key_width
		notehead(x + 6, offset + 13, pad == 0)
		text(["HAT", "SN", "KICK"][pad] if size.x < 540 else PAD_NAMES[pad], x + 17, offset + 6, 10 if size.x < 540 else 11)
	var has_hands := false
	for tick in range(8):
		var hands: Array = notation.sticking[tick]
		has_hands = has_hands or not hands.is_empty()
		text("+".join(hands), note_start + float(tick) * step, offset + 152, 11, INK, true)
	if has_hands:
		text("R/L suggested", left, offset + 153, 10)
