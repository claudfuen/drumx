extends Control
## A quiet coaching instrument: current pace, one instruction, one destination.
const Fonts = preload("res://scripts/main_menu.gd")
const PAPER = Color("f0f2e8")
const MUTED = Color("92a5a3")
const LIME = Color("cbe880")
var bpm := 60
var guidance := 0
var checkpoint := false
var recalled := false
var title := "Settle into the pulse."
var detail := "One click. One stroke. Count 1, 2, 3, 4."
var caption := "COACHED PACE"
var font: Font = Fonts.make_font(400)
var strong: Font = Fonts.make_font(600)

func _ready() -> void:
	custom_minimum_size.y = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_plan(pace: int, mode: int, decision: Dictionary, heading: String, explanation: String) -> void:
	bpm = pace
	guidance = mode
	checkpoint = bool(decision.get("checkpoint_earned", false))
	recalled = bool(decision.get("recall_earned", false))
	title = heading
	detail = explanation
	accessibility_name = "%s. %d BPM. %s. %s. Checkpoint %s." % [caption, bpm, title, detail, "earned" if checkpoint else "72 BPM"]
	queue_redraw()

func write(value: String, at: Vector2, point_size: int, color: Color, width: float = -1, bold: bool = false) -> void:
	var face: Font = strong if bold else font
	draw_string(face, at + Vector2(0, face.get_ascent(point_size)), value, HORIZONTAL_ALIGNMENT_LEFT, width, point_size, color)

func _draw() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("131c1d")
	panel.border_color = Color(LIME, 0.16)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(13)
	panel.shadow_color = Color(0, 0, 0, 0.16)
	panel.shadow_size = 8
	panel.shadow_offset = Vector2(0, 4)
	draw_style_box(panel, Rect2(Vector2.ZERO, size).grow(-1))
	# Fine upper light gives the panel a surface without a dashboard-like frame.
	draw_line(Vector2(18, 1), Vector2(size.x - 18, 1), Color(LIME, 0.13), 1, true)
	write(caption, Vector2(20, 15), 9, MUTED)
	write(str(bpm), Vector2(19, 32), 38, PAPER, -1, true)
	write("BPM", Vector2(76 if bpm < 100 else 98, 60), 10, MUTED)
	draw_line(Vector2(130, 22), Vector2(130, 78), Color(PAPER, 0.09), 1)
	var timeline_x := size.x - 224
	write(title, Vector2(151, 23), 17, PAPER, timeline_x - 170, true)
	write(detail, Vector2(151, 52), 12, MUTED, timeline_x - 170)
	write("YOUR CHECKPOINT", Vector2(timeline_x, 16), 9, MUTED)
	var labels := ["60", "66", "72", "Recall"]
	for i in range(4):
		var point := Vector2(timeline_x + 10 + i * 53, 50)
		if i < 3: draw_line(point, point + Vector2(53, 0), Color(LIME, 0.18), 1, true)
		var earned := checkpoint if i == 2 else recalled if i == 3 else false
		var active: bool = (i == 3 and guidance > 0) or (guidance == 0 and bpm == [60, 66, 72, -1][i])
		if active: draw_circle(point, 9, Color(LIME, 0.10), true, -1, true)
		draw_circle(point, 4, LIME if earned or active else Color("2b3939"), true, -1, true)
		write(labels[i], point + Vector2(-8 if i < 3 else -14, 15), 10, LIME if earned or active else MUTED)
