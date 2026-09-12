extends RefCounted

const DataModel = preload("res://scripts/game_data.gd")

# Every write uses a unique fixture path. This never reads or modifies the
# player's normal progress-v1.json, starts a take, or opens a hardware source.
static func run_checks(engine: Object) -> Dictionary:
	var result := {"checks": 0, "failures": []}
	var check := func(ok: bool, label: String) -> void:
		result.checks += 1
		if not ok: result.failures.append(label)
	if engine == null or not engine.has_method("evaluate_pulse_tempo"):
		check.call(false, "Shared tempo evaluator is available")
		return result
	var prefix := "user://tempo-contract-%d-%d" % [Time.get_ticks_usec(), randi()]
	var suffixes := ["fresh", "legacy", "checkpoint", "correction", "history", "conditions", "old-policy", "short", "metadata", "corrupt", "malformed-coach", "provenance"]
	var paths: Array[String] = []
	for suffix in suffixes: paths.append(prefix + "-" + suffix + ".json")
	var fresh := _model(paths[0], engine)
	check.call(not fresh.course.is_empty(), "Course fixture loads the authored lessons")
	if fresh.course.is_empty(): return result
	check.call(not FileAccess.file_exists(paths[0]), "Loading a fresh profile does not write a file")
	var prefs: Dictionary = fresh.pulse_preferences()
	check.call(prefs.intent == "guided" and prefs.guided == {"bpm": 60, "bars": 16, "guidance": 0}, "Fresh player starts Guided at 60 with sixteen bars")
	check.call(fresh.frontier() == 0 and not fresh.cleared(0), "Fresh profile starts at the pulse without invented evidence")
	check.call(fresh.remember_pulse("free", 108, 8, 2), "Free-practice plan saves")
	check.call(fresh.remember_pulse("guided", 66, 16, 0), "Guided plan saves independently")
	var reopened := _model(paths[0], engine)
	check.call(not reopened.blocked and reopened.pulse_preferences().intent == "guided", "Selected intent survives reopening")
	check.call(reopened.pulse_preferences().guided == {"bpm": 66.0, "bars": 16.0, "guidance": 0.0}, "Guided plan survives reopening")
	check.call(reopened.pulse_preferences().free == {"bpm": 108.0, "bars": 8.0, "guidance": 2.0}, "Free plan survives Guided changes and reopening")
	check.call(reopened.remember_pulse("free", 108, 8, 2), "Free intent can be reselected without replacing Guided")
	var free_reopened := _model(paths[0], engine)
	check.call(free_reopened.pulse_preferences().intent == "free" and float(free_reopened.pulse_preferences().guided.bpm) == 66, "Both independent plans persist across intent changes")
	var prior_plan: Dictionary = free_reopened.save.duplicate(true)
	var prior_bytes := FileAccess.get_file_as_string(paths[0])
	check.call(not free_reopened.remember_pulse("guided", 90, 16, 0), "Unauthored Guided rung is rejected")
	check.call(free_reopened.save == prior_plan and FileAccess.get_file_as_string(paths[0]) == prior_bytes, "Rejected plan preserves memory and disk atomically")
	var blocked_path := prefix + "-missing-parent/progress.json"
	free_reopened.save_path = blocked_path
	check.call(not free_reopened.remember_pulse("guided", 72, 16, 0), "Unavailable output path reports persistence failure")
	check.call(free_reopened.save == prior_plan, "Failed write restores the prior pair of plans")
	free_reopened.save_path = paths[0]

	var legacy_settings := _settings(72, 4)
	for key in ["tempo_policy", "live_feedback", "monitoring", "calibration_ms"]: legacy_settings.erase(key)
	var legacy := {"version": 1, "selected": 1, "read": {}, "settings": {}, "attempts": [_archived("legacy-take", legacy_settings, _score(4))]}
	check.call(_write(paths[1], JSON.stringify(legacy)), "Legacy fixture is written separately")
	var migrated := _model(paths[1], engine)
	check.call(not migrated.blocked and migrated.frontier() == 1, "Migration retains access to the previously unlocked second lesson")
	check.call(not migrated.cleared(0) and not migrated.pulse_decision(_settings()).get("checkpoint_earned", true), "Legacy completion never gains new checkpoint evidence")
	check.call(migrated.pulse_preferences().intent == "free" and int(migrated.pulse_preferences().free.bars) == 4, "Migration preserves old pulse settings as Free practice")
	check.call(migrated.remember_pulse("guided", 60, 16, 0), "Migrated player can explicitly choose Guided")
	var migrated_again := _model(paths[1], engine)
	check.call(migrated_again.frontier() == 1 and not migrated_again.cleared(0), "Legacy access survives persistence without becoming checkpoint credit")

	var checkpoint := _model(paths[2], engine)
	var settings := _settings()
	check.call(checkpoint.remember_pulse("free", 72, 16, 0), "Free can select the exact checkpoint conditions")
	check.call(checkpoint.record("free-checkpoint-1", 0, _score(16), settings), "First current-policy Free checkpoint take archives")
	check.call(not checkpoint.pulse_decision(settings).get("checkpoint_earned", true), "One strong take is not a repeated checkpoint")
	check.call(checkpoint.record("free-checkpoint-2", 0, _score(16), settings), "Second comparable Free checkpoint take archives")
	check.call(checkpoint.pulse_decision(settings).get("checkpoint_earned", false), "Exact current-policy checkpoint can be earned in Free practice")
	check.call(checkpoint.frontier() == 1, "An earned MIDI checkpoint unlocks the second lesson")
	var checkpoint_again := _model(paths[2], engine)
	check.call(checkpoint_again.pulse_decision(settings).get("checkpoint_earned", false) and checkpoint_again.frontier() == 1, "Checkpoint and course access survive reopening")
	check.call(not fresh.pulse_decision(settings).get("checkpoint_earned", true), "Independent fixture profiles never share evidence")

	var corrections := _model(paths[3], engine)
	check.call(corrections.record("corrected-a", 0, _score(16), settings) and corrections.record("corrected-b", 0, _score(16), settings), "Correction fixture earns its own checkpoint")
	check.call(corrections.pulse_decision(settings).get("checkpoint_earned", false), "Correction fixture starts with repeated evidence")
	var poor := _score(16, 20, 20)
	check.call(corrections.record("corrected-b", 0, poor, settings), "Late correction replaces an archived take")
	check.call(corrections.save.attempts.size() == 2 and not corrections.pulse_decision(settings).get("checkpoint_earned", true), "Correction removes checkpoint credit without duplicating the ID")
	var correction_again := _model(paths[3], engine)
	check.call(not correction_again.pulse_decision(settings).get("checkpoint_earned", true) and correction_again.frontier() == 0, "Revoked checkpoint stays revoked for the new profile after reopening")
	check.call(correction_again.record("corrected-b", 0, _score(16), settings) and correction_again.pulse_decision(settings).get("checkpoint_earned", false), "A corrected delayed score can restore the checkpoint")

	var history := _model(paths[4], engine)
	check.call(history.record("historic-a", 0, _score(16), settings) and history.record("historic-b", 0, _score(16), settings), "Historical checkpoint fixture starts with two strong takes")
	for index in range(4): check.call(history.record("later-difficult-%d" % index, 0, poor, settings), "Later difficult take %d archives" % index)
	var historical: Dictionary = history.pulse_decision(settings)
	check.call(historical.get("checkpoint_earned", false) and historical.get("recent_qualifying") == 0, "Later difficult days do not erase historical repeated evidence")
	check.call(_model(paths[4], engine).pulse_decision(settings).get("checkpoint_earned", false), "Historical checkpoint survives reopening after later misses")

	var separated := _model(paths[5], engine)
	var another_source := settings.duplicate(true)
	another_source.source = "fixture-midi:second-source"
	check.call(separated.record("source-a", 0, _score(16), settings) and separated.record("source-b", 0, _score(16), another_source), "Distinct-source takes archive independently")
	check.call(not separated.pulse_decision(settings).get("checkpoint_earned", true) and not separated.pulse_decision(another_source).get("checkpoint_earned", true) and separated.frontier() == 0, "Two sources cannot pool one strong take each into a checkpoint")
	check.call(separated.record("source-a-repeat", 0, _score(16), settings), "One source obtains its own second comparable take")
	check.call(separated.pulse_decision(settings).get("checkpoint_earned", false) and not separated.pulse_decision(another_source).get("checkpoint_earned", true), "Coaching evidence stays specific to the selected condition group")
	var reordered := settings.duplicate(true)
	for aliases in reordered.mapping: aliases.reverse()
	check.call(separated.pulse_decision(reordered).get("checkpoint_earned", false), "Alias ordering does not change the same logical mapping")
	var remapped := settings.duplicate(true)
	remapped.mapping = [[42, 44, 46], [39, 40], [35, 36]]
	check.call(not separated.pulse_decision(remapped).get("checkpoint_earned", true), "A changed MIDI note mapping is a distinct condition group")
	var monitor_changed := settings.duplicate(true)
	monitor_changed.monitoring = true
	check.call(not separated.pulse_decision(monitor_changed).get("checkpoint_earned", true), "Monitoring changes do not pool checkpoint evidence")

	var old_policy := _model(paths[6], engine)
	var old_settings := settings.duplicate(true)
	old_settings.tempo_policy = 2
	check.call(old_policy.record("unknown-policy-a", 0, _score(16), old_settings) and old_policy.record("unknown-policy-b", 0, _score(16), old_settings), "A valid other-policy archive remains readable")
	check.call(not old_policy.pulse_decision(settings).get("checkpoint_earned", true) and old_policy.frontier() == 0, "Other-policy history is never stamped with current evidence")
	var short := _model(paths[7], engine)
	var short_settings := _settings(72, 4)
	check.call(short.record("short-a", 0, _score(4), short_settings) and short.record("short-b", 0, _score(4), short_settings), "Short Free phrases remain valid archived practice")
	check.call(not short.pulse_decision(settings).get("checkpoint_earned", true) and short.frontier() == 0, "Perfect short phrases do not satisfy sixteen-bar checkpoint evidence")

	var metadata := _model(paths[8], engine)
	var missing := settings.duplicate(true)
	missing.erase("monitoring")
	check.call(not metadata.record("missing-metadata", 0, _score(16), missing) and metadata.save.attempts.is_empty(), "Policy-tagged take with missing monitoring provenance is rejected")
	var interrupted := _score(16)
	interrupted.naturally_completed = false
	check.call(not metadata.record("interrupted", 0, interrupted, settings) and metadata.save.attempts.is_empty(), "Interrupted take is not archived as completed evidence")
	var invalid_save := {"version": 1, "selected": 0, "read": {}, "settings": {}, "attempts": [_archived("invalid-provenance", missing, _score(16))]}
	var invalid_bytes := JSON.stringify(invalid_save)
	check.call(_write(paths[8], invalid_bytes), "Invalid-provenance file fixture is isolated")
	var rejected := _model(paths[8], engine)
	check.call(rejected.blocked and not rejected.error.is_empty(), "Invalid persisted policy metadata blocks loading explicitly")
	check.call(not rejected.remember_pulse("guided", 60, 16, 0) and FileAccess.get_file_as_string(paths[8]) == invalid_bytes, "Invalid metadata file is preserved after attempted preference change")
	var corrupt_bytes := "{ incomplete fixture JSON"
	check.call(_write(paths[9], corrupt_bytes), "Malformed JSON fixture is isolated")
	var corrupt := _model(paths[9], engine)
	check.call(corrupt.blocked and not corrupt.remember_pulse("free", 96, 8, 0) and FileAccess.get_file_as_string(paths[9]) == corrupt_bytes, "Malformed save is preserved and cannot be overwritten by preference changes")
	var bad_coach: Dictionary = checkpoint.save.duplicate(true)
	bad_coach.tempo_coach.guided.bpm = 90
	var bad_coach_bytes := JSON.stringify(bad_coach)
	check.call(_write(paths[10], bad_coach_bytes), "Invalid Guided-plan fixture is isolated")
	var rejected_coach := _model(paths[10], engine)
	check.call(rejected_coach.blocked and FileAccess.get_file_as_string(paths[10]) == bad_coach_bytes, "Malformed saved Guided plan does not silently reset or destroy progress")
	var provenance := _model(paths[11], engine)
	var supplied_settings := _settings()
	check.call(provenance.record("captured-intent", 0, _score(16), supplied_settings), "Captured-intent fixture archives independently")
	supplied_settings.bpm = 96
	supplied_settings.mapping[1][0] = 39
	check.call(float(provenance.save.attempts[0].settings.bpm) == 72 and int(provenance.save.attempts[0].settings.mapping[1][0]) == 38, "Later caller mutations cannot rewrite archived intent or nested mapping")
	check.call(provenance.remember_pulse("free", 96, 16, 0), "Unrelated preference change can persist after an archived take")
	var provenance_again := _model(paths[11], engine)
	check.call(float(provenance_again.save.attempts[0].settings.bpm) == 72 and int(provenance_again.save.attempts[0].settings.mapping[1][0]) == 38, "Reopening retains captured intent rather than later mutable caller settings")
	_cleanup(paths)
	return result

static func _model(path: String, engine: Object) -> RefCounted:
	var model = DataModel.new()
	model.save_path = path
	model.tempo_engine = engine
	if model.load_course(): model.load_progress()
	return model

static func _settings(bpm: int = 72, bars: int = 16) -> Dictionary:
	return {"bpm": bpm, "bars": bars, "guidance": 0, "source": "fixture-midi:primary", "mapping": [[42, 44, 46], [38, 40], [35, 36]], "tempo_policy": 1, "live_feedback": true, "monitoring": false, "calibration_ms": 0}

static func _score(bars: int, matched: int = -1, on_time: int = -1) -> Dictionary:
	var expected := bars * 4
	if matched < 0: matched = expected
	if on_time < 0: on_time = matched
	return {"naturally_completed": true, "expected": expected, "matched": matched, "on_time": on_time, "missed": expected - matched, "extra": 0, "best_streak": on_time}

static func _archived(id: String, settings: Dictionary, score: Dictionary) -> Dictionary:
	return {"id": id, "lesson": "find-the-pulse", "version": "find-the-pulse-v1", "settings": settings.duplicate(true), "points": DataModel.points(score, true), "best_streak": score.best_streak, "expected": score.expected, "matched": score.matched, "on_time": score.on_time, "missed": score.missed, "extra": score.extra}

static func _write(path: String, contents: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(contents)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

static func _cleanup(paths: Array[String]) -> void:
	for path in paths:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
