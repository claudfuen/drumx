extends Control
## The compact take header from native/macos/DrumxScoreViews.swift.
const Fonts = preload("res://scripts/main_menu.gd")
const Model = preload("res://scripts/game_data.gd")
const INK = Color(0.921, 0.938, 0.900)
const MUTED = Color(0.574, 0.649, 0.645)
const QUIET = Color(0.240, 0.315, 0.320)
const GOLD = Color(0.920, 0.751, 0.449)
var score := -1
var combo := 0
var best := -1
var state := "COUNT-IN"
var font: Font = Fonts.make_font(500)
var bold: Font = Fonts.make_font(600)

func _ready() -> void:
	custom_minimum_size = Vector2(420, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_score(snapshot: Dictionary, reveal: bool, previous_best: int, caption: String) -> void:
	score = Model.points(snapshot, false) if reveal else -1
	combo = int(snapshot.get("streak", 0)) if reveal else 0
	best = previous_best
	state = caption
	queue_redraw()

func text(value: String, at: Vector2, point_size: int, color: Color, strong: bool = false) -> void:
	var face: Font = bold if strong else font
	draw_string(face, at + Vector2(0, face.get_ascent(point_size)), value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, color)

func _draw() -> void:
	if score < 0:
		text(state, Vector2(0, 14), 11, MUTED, true)
		return
	var count := Model.stars(score, false)
	for index in range(5):
		var points := PackedVector2Array()
		for vertex in range(10):
			var angle := -PI / 2 + float(vertex) * PI / 5
			var radius := 8.0 * (1.0 if vertex % 2 == 0 else 0.46)
			points.append(Vector2(9 + index * 20, 13) + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, GOLD if index < count else Color(QUIET, 0.28))
		if index >= count:
			points.append(points[0])
			draw_polyline(points, Color(MUTED, 0.28), 1, true)
	var thresholds := [0, 4000, 6000, 7500, 9000, 10000]
	var progress := float(score - thresholds[count]) / float(thresholds[count + 1] - thresholds[count])
	draw_rect(Rect2(1, 33, 96, 2), Color(QUIET, 0.65))
	draw_rect(Rect2(1, 33, 96 * clampf(progress, 0, 1), 2), Color(GOLD, 0.82))
	text(str(score), Vector2(118, 0), 25, INK, true)
	text("POINTS", Vector2(119, 29), 11, MUTED)
	text("%d COMBO" % combo, Vector2(274, 4), 13, INK, true)
	if best >= 0:
		text("BEST %d" % best, Vector2(274, 25), 11, MUTED)
