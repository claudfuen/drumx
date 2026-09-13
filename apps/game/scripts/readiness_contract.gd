extends RefCounted

const DataModel = preload("res://scripts/game_data.gd")

# Mirrored against the native unlock fixtures. No player files or device access.
static func run_checks() -> Dictionary:
	var result := {"checks": 0, "failures": []}
	var check := func(ok: bool, label: String) -> void:
		result.checks += 1
		if not ok: result.failures.append(label)
	var model := DataModel.new()
	check.call(model.load_course(), "Readiness loads the complete authored catalog")
	model.ensure_tempo_coach(false)
	model.ensure_readiness(false)
	var lesson := 6
	var good := _attempt(model, lesson, "one")
	var good2 := _attempt(model, lesson, "two")
	check.call(model.readiness_status(lesson, good.settings).eligible, "Checkpoint settings are recognized before first take")
	model.save.attempts = [good]
	check.call(not model.readiness_status(lesson).checkpoint and model.readiness_status(lesson).passing == 1, "One steady take is evidence but not a checkpoint")
	model.save.attempts = [good, good]
	check.call(not model.readiness_status(lesson).checkpoint, "The same take identity cannot supply both successes")
	model.save.attempts = [good, good2]
	check.call(model.readiness_status(lesson).checkpoint, "Two comparable guided takes earn repeatability")
	model.save.attempts = [_attempt(model, lesson, "boundary-one", [128, 32, 26], [128, 32, 23], 19), _attempt(model, lesson, "boundary-two", [128, 32, 26], [128, 32, 23], 19)]
	check.call(model.readiness_status(lesson).checkpoint, "Integer per-pad and extras boundaries qualify")
	var no_kick := _attempt(model, lesson, "no-kick", [128, 32, 0])
	check.call(float(no_kick.matched) / float(no_kick.expected) > 0.8, "Missing every kick exceeds the obsolete aggregate threshold")
	model.save.attempts = [no_kick, _attempt(model, lesson, "no-kick-two", [128, 32, 0])]
	check.call(not model.readiness_status(lesson).checkpoint, "Hat density cannot conceal every missing kick")
	model.save.attempts = [good, no_kick, good2]
	check.call(model.readiness_status(lesson).checkpoint, "Two steady takes within three comparable attempts qualify")
	model.save.attempts = [good, good2, no_kick, _attempt(model, lesson, "no-kick-two", [128, 32, 0])]
	check.call(model.readiness_status(lesson).checkpoint, "Later practice cannot erase an earned checkpoint")
	model.save.attempts = [good, no_kick, _attempt(model, lesson, "no-kick-two", [128, 32, 0]), good2]
	check.call(not model.readiness_status(lesson).checkpoint, "Successes outside every three-window cannot pool")
	var changed: Array = []
	for change in [{"bpm": 60}, {"guidance": 1}, {"guidance": 2}, {"bars": 4}, {"source": "different-kit"}, {"hand_hints": false}, {"calibration_ms": 0.25}, {"monitoring": true}]:
		var take := good2.duplicate(true)
		take.settings.merge(change, true)
		changed.append(take)
	for take in changed:
		model.save.attempts = [good, take]
		check.call(not model.readiness_status(lesson).checkpoint, "Changed tempo, guidance, phrase, input or hints cannot pool")
	for bad in [_attempt(model, lesson, "extras", [], [], 20), _attempt(model, lesson, "timing", [], [128, 32, 22]), _attempt(model, lesson, "coverage", [128, 32, 25])]:
		model.save.attempts = [bad, good]
		check.call(not model.readiness_status(lesson).checkpoint, "Extras and per-instrument thresholds exclude weak takes")
	var aliases_one := good.duplicate(true)
	aliases_one.settings.mapping = [[42, 44], [38, 40], [35, 36]]
	var aliases_two := good2.duplicate(true)
	aliases_two.settings.mapping = [[44, 42], [40, 38], [36, 35]]
	model.save.attempts = [aliases_one, aliases_two]
	check.call(model.readiness_status(lesson, aliases_two.settings).checkpoint, "Alias order does not alter a mapping's meaning")
	var corrupt := good.duplicate(true)
	corrupt.pads[0].extra = 1
	check.call(not model.valid_attempt(corrupt), "Inconsistent per-pad and aggregate totals are invalid archive evidence")
	var missing := good.duplicate(true)
	missing.erase("pads")
	check.call(not model.valid_attempt(missing), "New checkpoint policy cannot omit per-pad evidence")
	var incorrect_chart := _attempt(model, lesson, "wrong-chart")
	incorrect_chart.pads[0].expected = 160
	incorrect_chart.pads[0].matched = 160
	incorrect_chart.pads[0].on_time = 160
	for pad in [1, 2]:
		incorrect_chart.pads[pad].expected = 16
		incorrect_chart.pads[pad].matched = 16
		incorrect_chart.pads[pad].on_time = 16
	check.call(model.valid_attempt(incorrect_chart) and not model.authored_pads(incorrect_chart, lesson), "Internally valid totals still need authored per-pad chart counts")
	var old := good.duplicate(true)
	old.erase("pads")
	old.settings.erase("readiness_policy")
	check.call(model.valid_attempt(old), "Legacy totals remain readable without invented per-pad evidence")
	model.save.erase("readiness")
	model.save.attempts = [old]
	model.ensure_readiness(true)
	check.call(model.frontier() == lesson + 1 and not model.cleared(lesson), "Old aggregate completion preserves access without a new checkpoint")
	model.save.selected = model.course.lessons.size() - 1
	model.save.attempts.append(_attempt(model, model.save.selected, "sandbox"))
	model.ensure_readiness(true)
	check.call(model.frontier() == lesson + 1, "New sandbox selection cannot increase frozen legacy access")
	for index in range(1, model.course.lessons.size()):
		model.save.attempts = [_attempt(model, index, "one"), _attempt(model, index, "two")]
		check.call(model.readiness_status(index).checkpoint, "Every authored non-pulse lesson can earn its own checkpoint")
		check.call(model.needs_reading(index) == (index + 1 < model.course.lessons.size() and model.course.lessons[index].chapter != model.course.lessons[index + 1].chapter), "Reading gates follow authored chapter boundaries")
	model.save.attempts = []
	model.save.selected = model.course.lessons.size() - 1
	check.call(model.valid_save(model.save), "Last authored lesson is a valid saved selection")
	model.save.selected += 1
	check.call(not model.valid_save(model.save), "Selection beyond the actual course is rejected")
	model.save.selected = 0
	# Completed takes stay pending when storage fails and publish only after recovery.
	var prefix := "user://readiness-contract-%d-%d" % [Time.get_ticks_usec(), randi()]
	model.save_path = prefix + "/unavailable.json"
	var score := _snapshot(good)
	check.call(not model.record("pending-one", lesson, score, good.settings), "Unavailable storage does not publish the first checkpoint take")
	check.call(not model.record("pending-two", lesson, score, good.settings), "Second failed write remains recoverable")
	check.call(model.pending_save_count() == 2 and not model.readiness_status(lesson).checkpoint, "Pending results cannot award a checkpoint")
	model.save_path = prefix + ".json"
	check.call(model.retry_pending() and model.readiness_status(lesson).checkpoint, "Durable recovery publishes both completed takes together")
	var reopened := DataModel.new()
	reopened.load_course()
	reopened.save_path = model.save_path
	reopened.load_progress()
	check.call(not reopened.blocked and reopened.readiness_status(lesson).checkpoint, "Optional pad evidence and checkpoint survive a disk round-trip")
	for changed_score in [{"naturally_completed": false}, {"bpm": 60}, {"guidance": 1}, {"duration_seconds": 1}, {"elapsed_seconds": 1}]:
		var invalid_snapshot := score.duplicate(true)
		invalid_snapshot.merge(changed_score, true)
		check.call(not model.record("invalid", lesson, invalid_snapshot, good.settings), "Natural completion and captured transport conditions must agree")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(model.save_path))
	return result

static func _attempt(model: RefCounted, index: int, identifier: String, matches: Array = [], on_times: Array = [], extra: int = 0) -> Dictionary:
	var expected := [0, 0, 0]
	for event in model.course.lessons[index].events: expected[int(event.pad)] += 16
	if matches.is_empty(): matches = expected.duplicate()
	if on_times.is_empty(): on_times = matches.duplicate()
	var pads: Array = []
	var take := {"id": identifier, "lesson": model.course.lessons[index].id, "version": model.course.lessons[index].version,
		"settings": {"bpm": model.course.lessons[index].bpm, "bars": 16, "guidance": 0, "source": "fixture-kit", "mapping": [[42], [38], [36]], "readiness_policy": 1, "hand_hints": true, "live_feedback": true, "monitoring": false, "calibration_ms": 0},
		"expected": 0, "matched": 0, "missed": 0, "on_time": 0, "extra": extra, "best_streak": 0}
	for pad in range(3):
		pads.append({"expected": expected[pad], "matched": matches[pad], "missed": expected[pad] - matches[pad], "on_time": on_times[pad], "extra": extra if pad == 0 else 0})
		for key in ["expected", "matched", "missed", "on_time"]: take[key] += pads[pad][key]
	take.best_streak = take.on_time
	take.pads = pads
	take.points = DataModel.points(take, true)
	return take

static func _snapshot(take: Dictionary) -> Dictionary:
	var result := take.duplicate(true)
	result.naturally_completed = true
	result.bpm = take.settings.bpm
	result.guidance = take.settings.guidance
	result.duration_seconds = float(take.settings.bars) * 240.0 / float(take.settings.bpm)
	result.elapsed_seconds = result.duration_seconds
	return result
