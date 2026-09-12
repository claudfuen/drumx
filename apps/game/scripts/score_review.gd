extends Control
## Compact result and comparable-take strip from the original Mac score view.
const Fonts = preload("res://scripts/main_menu.gd")
const Model = preload("res://scripts/game_data.gd")
const PAPER = Color(0.921, 0.938, 0.900)
const MUTED = Color(0.574, 0.649, 0.645)
const GOLD = Color(0.920, 0.751, 0.449)
var font: Font = Fonts.make_font(500)
var bold: Font = Fonts.make_font(600)
var points := 0
var stars := 0
var previous_best := -1
var complete := false
var current_id := ""
var recent: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(0, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_score(snapshot: Dictionary, best: int, attempts: Array, saved_id: String) -> void:
	complete = bool(snapshot.get("naturally_completed", false))
	points = Model.points(snapshot, complete)
	stars = Model.stars(points, complete)
	previous_best = best
	current_id = saved_id
	recent = attempts.slice(maxi(0, attempts.size() - 6))
	queue_redraw()

func text(value: String, at: Vector2, point_size: int = 11, color: Color = MUTED, centered: bool = false, strong: bool = false) -> void:
	var face: Font = bold if strong else font
	var x: float = at.x - (face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x / 2 if centered else 0)
	draw_string(face, Vector2(x, at.y + face.get_ascent(point_size)), value, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size, color)

func _draw() -> void:
	for index in range(5):
		var polygon := PackedVector2Array()
		for vertex in range(10):
			var angle := -PI / 2 + float(vertex) * PI / 5
			var radius := 14.0 * (1.0 if vertex % 2 == 0 else 0.46)
			polygon.append(Vector2(14 + index * 34, 22) + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(polygon, GOLD if index < stars else Color(MUTED, 0.08))
		if index >= stars:
			polygon.append(polygon[0])
			draw_polyline(polygon, Color(MUTED, 0.28), 1, true)
	text(str(points), Vector2(199, 0), 34, PAPER, false, true)
	text("/ 10,000", Vector2(342, 20), 12)
	var x := maxf(456, size.x - 328)
	var saved := complete and current_id != ""
	if previous_best >= 0:
		text("PREVIOUS BEST  %d" % previous_best, Vector2(x, 5))
		var delta := points - previous_best
		var copy := "Finish the phrase to save a result."
		if complete and not saved: copy = "Result not saved. See the message below."
		elif saved: copy = "+%d · NEW PERSONAL BEST" % delta if delta > 0 else "PERSONAL BEST MATCHED" if delta == 0 else "%d points to your best" % -delta
		text(copy, Vector2(x, 25), 12, GOLD if saved and delta >= 0 else MUTED)
	else:
		text("FIRST COMPARABLE TAKE" if saved else "TAKE NOT SAVED" if complete else "YOUR NEXT BENCHMARK", Vector2(x, 5))
		text("Complete another take to compare." if saved else "Complete a take to start your comparison.", Vector2(x, 25), 12)
	text("RECENT TAKES", Vector2(0, 78))
	text("Same lesson and settings", Vector2(0, 96))
	if recent.is_empty():
		text("No saved comparable takes yet.", Vector2(200, 89), 12)
		return
	var cell_width := maxf(50, (size.x - 212) / 6)
	for index in range(recent.size()):
		var attempt: Dictionary = recent[index]
		var current: bool = attempt.id == current_id
		var center := 204 + index * cell_width + cell_width / 2
		var color := GOLD if current else MUTED
		text(str(int(attempt.points)), Vector2(center, 63), 11, PAPER if current else MUTED, true)
		var height := clampf(float(attempt.points), 0, 10000) / 10000 * 26
		var width := minf(54, cell_width - 22)
		draw_rect(Rect2(center - width / 2, 106, width, 1), Color(MUTED, 0.22))
		draw_rect(Rect2(center - width / 2, 106 - height, width, height), Color(color, 0.88 if current else 0.46))
		text("NOW" if current else str(index + 1), Vector2(center, 113), 11, color, true, current)
