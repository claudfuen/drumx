extends RefCounted
const Notation = preload("res://scripts/drum_notation.gd")
var checks := 0
var failures := 0

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("NOTATION_FAIL ", detail)

func run_checks(root: Window) -> Dictionary:
	var course = JSON.parse_string(FileAccess.get_file_as_string("res://data/course.json"))
	for lesson in course.lessons:
		var model := Notation.notation_model(lesson.events)
		check(model.valid, "authored lesson supported: " + lesson.id)
		var expected: Array = []
		for event in lesson.events:
			expected.append(roundi(float(event.beat) * 2) * 3 + int(event.pad))
		expected.sort()
		var reconstructed: Array = []
		for voice in model.voices:
			check(voice.beats.size() == 4, "voice spells four numbered beats")
			for beat in range(4):
				var plan = voice.beats[beat]
				for half in range(2):
					for pad in plan.first if half == 0 else plan.second:
						reconstructed.append((beat * 2 + half) * 3 + pad)
						check((pad == 2) == voice.down, "kick isolated in lower voice")
				if plan.kind == "quarter_rest":
					check(plan.first.is_empty() and plan.second.is_empty(), "rest never masks an authored strike")
		reconstructed.sort()
		check(reconstructed == expected, "voice spelling neither drops nor invents an attack")
		check(model.counts.size() == (8 if model.eighths else 4), "counts use smallest authored subdivision")
		check(model.counts[0].text == "1", "integer beat labels")
	var hats := Notation.notation_model([{ "beat": 0.0, "pad": 0 }, { "beat": 0.5, "pad": 0 }])
	check(hats.voices.size() == 1 and not hats.voices[0].down, "hi-hat-only omits silent lower voice")
	check(hats.voices[0].beats[0].kind == "eighth_pair", "two eighth attacks share a beam")
	check(hats.voices[0].beats[1].kind == "quarter_rest", "silent beat receives a quarter rest")
	var kick := Notation.notation_model([{ "beat": 1.5, "pad": 2.0 }])
	check(kick.voices.size() == 1 and kick.voices[0].down, "kick-only omits silent upper voice, accepts integral JSON pads")
	check(kick.voices[0].beats[1].kind == "eighth_rest_note", "offbeat uses eighth rest then flagged note")
	var chord := Notation.notation_model([{ "beat": 0, "pad": 0 }, { "beat": 0, "pad": 1 }, { "beat": 0, "pad": 2 }])
	check(chord.voices.size() == 2, "simultaneous kit attacks use two voices")
	check(chord.voices[0].beats[0].first == [0, 1], "hi-hat and snare form one upper chord")
	check(chord.voices[1].beats[0].first == [2], "kick is independent lower quarter")
	var empty := Notation.notation_model([])
	check(empty.valid and empty.voices.size() == 1, "empty bar matches native single rest voice")
	check(not Notation.notation_model([{"beat":3.9999999,"pad":1}]).valid, "near-barline tolerance cannot index a ninth slot")
	for bad in [[{"beat": 0.25, "pad": 1}], [{"beat": -0.5, "pad": 1}], [{"beat": 4, "pad": 1}], [{"beat": NAN, "pad": 1}], [{"beat": INF, "pad": 1}], [{"beat": 0, "pad": 3}], [{"beat": 0, "pad": 1.5}], [{"beat": 0, "pad": NAN}], [{"beat": 0, "pad": 1}, {"beat": 0, "pad": 1}], [{"beat": "0", "pad": 1}], [null]]:
		check(not Notation.notation_model(bad).valid, "unsupported rhythm fails closed")
	var view := Notation.new()
	root.add_child(view)
	view.lesson_title = "Offbeat kick"
	view.authored = [{"beat": 1.5, "pad": 2}]
	check(view.custom_minimum_size == Vector2(320,172), "original logical minimum")
	check(view.accessibility_name.contains("And of 2: Kick"), "accessible counts explain offbeat kick")
	check(view.accessibility_name.contains("Count 1: no strike"), "accessible rests are explicit")
	check(not view.accessibility_name.contains("Hi-hat and Snare"), "no invented chord description")
	view.authored = [{"beat": 0.25, "pad": 1}]
	check(view.accessibility_name == "Offbeat kick. Notation is unavailable for this rhythm.", "invalid update clears previous accessible rhythm")
	# Exercise queued draw commands through CanvasItem's draw notification with
	# a headless renderer. This catches invalid polygon/path calls, not appearance.
	for lesson in course.lessons:
		view.lesson_title = lesson.title
		view.authored = lesson.events
		view.size = Vector2(880,172)
		view.notification(CanvasItem.NOTIFICATION_DRAW)
	view.free()
	return {"checks": checks, "failures": failures}
