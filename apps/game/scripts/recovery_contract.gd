extends RefCounted

const DataModel = preload("res://scripts/game_data.gd")

# Unique disposable paths only. These checks exercise actual atomic file writes
# and recovery without touching the player's archive or any input/audio device.
static func run_checks(engine: Object = null) -> Dictionary:
	var result := {"checks": 0, "failures": []}
	var check := func(ok: bool, label: String) -> void:
		result.checks += 1
		if not ok: result.failures.append(label)
	var prefix := "user://recovery-contract-%d-%d" % [Time.get_ticks_usec(), randi()]
	var target := prefix + ".json"
	var unavailable := prefix + "/progress.json"
	var model := DataModel.new()
	model.load_course()
	model.save_path = target
	model.load_progress()
	var settings := {"bpm": 72, "bars": 16, "guidance": 0, "source": "fixture-kit",
		"mapping": [[42], [38], [36]], "tempo_policy": 1, "live_feedback": true,
		"monitoring": false, "calibration_ms": 0}
	var score := {"naturally_completed": true, "expected": 64, "matched": 64,
		"on_time": 64, "missed": 0, "extra": 0, "best_streak": 64}
	check.call(model.record("saved-before", 0, score, settings), "Existing result is durably saved")
	var prior_bytes := FileAccess.get_file_as_string(target)
	var prior_revision := model.progress_revision
	model.save_path = unavailable
	check.call(not model.record("waiting-one", 0, score, settings), "Unavailable storage fails visibly")
	check.call(model.pending_save_count() == 1 and model.save.attempts.size() == 1, "Failed result is retained separately from committed progress")
	check.call(model.progress_revision == prior_revision and FileAccess.get_file_as_string(target) == prior_bytes, "Failed save does not publish progress or change prior archive")
	settings.bpm = 84
	check.call(model.pending_attempts["waiting-one"].settings.bpm == 72, "Captured settings are deep copied before another take changes tempo")
	check.call(not model.record("waiting-two", 0, score, settings) and model.pending_save_count() == 2, "A new take retains both unsaved IDs")
	settings.bpm = 72
	var corrected := score.duplicate(true)
	corrected.on_time = 60
	corrected.best_streak = 60
	check.call(not model.record("waiting-one", 0, corrected, settings), "Late correction stays pending while storage is unavailable")
	check.call(model.pending_save_count() == 2 and model.pending_attempts["waiting-one"].on_time == 60, "Latest correction replaces one queued payload without duplicating it")
	settings.bpm = 96
	check.call(not model.record("waiting-one", 0, score, settings), "A correction cannot rewrite captured tempo")
	check.call(model.pending_attempts["waiting-one"].settings.bpm == 72 and model.pending_attempts["waiting-one"].on_time == 60, "Rejected provenance change preserves original queued result")
	check.call(not model.retry_pending() and model.pending_save_count() == 2, "Repeated failure retains the entire queue")
	model.save_path = target
	check.call(model.retry_pending() and model.pending_save_count() == 0, "Storage recovery flushes all waiting results")
	check.call(model.save.attempts.size() == 3 and model.save.attempts[1].on_time == 60 and model.save.attempts[2].settings.bpm == 84, "Recovery preserves distinct conditions and latest corrected score")
	check.call(model.progress_revision == prior_revision + 1 and model.error.is_empty(), "A durable recovery publishes progress and clears failure")
	check.call(model.retry_pending() and model.save.attempts.size() == 3, "Repeated recovery does not duplicate records")
	var reopened := DataModel.new()
	reopened.load_course()
	reopened.save_path = target
	reopened.load_progress()
	check.call(not reopened.blocked and reopened.save.attempts == model.save.attempts, "All recovered results survive reopening")
	settings.bpm = 72
	check.call(not model.record("saved-before", 1, score, settings), "Existing take cannot be relabeled as another lesson")
	var partial := score.duplicate(true)
	partial.naturally_completed = false
	check.call(not model.record("partial", 0, partial, settings) and model.pending_save_count() == 0, "Interrupted take never enters completed queue")
	var invalid := score.duplicate(true)
	invalid.expected = 100
	check.call(not model.record("invalid", 0, invalid, settings) and model.pending_save_count() == 0, "Invalid counts never enter completed queue")
	var broken_path := prefix + "-corrupt.json"
	var file := FileAccess.open(broken_path, FileAccess.WRITE)
	file.store_string("preserve this unreadable archive")
	file.close()
	var blocked := DataModel.new()
	blocked.load_course()
	blocked.save_path = broken_path
	blocked.load_progress()
	check.call(blocked.blocked, "Unreadable archive blocks replacement")
	var empty_blocked := DataModel.new()
	empty_blocked.load_course()
	empty_blocked.save_path = broken_path
	empty_blocked.load_progress()
	check.call(not empty_blocked.retry_pending(true), "Explicit retry with no pending takes still preserves an unreadable archive")
	check.call(not blocked.record("after-corrupt", 0, score, settings) and blocked.pending_save_count() == 1, "Completed result survives an unreadable original archive")
	check.call(not blocked.retry_pending(true) and FileAccess.get_file_as_string(broken_path) == "preserve this unreadable archive", "Explicit retry never replaces an unreadable archive")
	file = FileAccess.open(broken_path, FileAccess.WRITE)
	file.store_string(prior_bytes)
	file.close()
	check.call(not blocked.retry_pending() and blocked.pending_save_count() == 1, "Automatic retry does not silently import a restored archive")
	check.call(blocked.retry_pending(true) and not blocked.blocked and blocked.save.attempts.size() == 2, "Explicit retry merges pending result into a valid restored archive")
	check.call(blocked.save.attempts[0].id == "saved-before" and blocked.save.attempts[1].id == "after-corrupt", "Restored archive and queued result both survive")
	var repaired_bytes := FileAccess.get_file_as_string(broken_path)
	check.call(empty_blocked.retry_pending(true) and not empty_blocked.blocked and empty_blocked.save.attempts.size() == 2, "Retry restores a repaired archive without requiring a new take")
	check.call(empty_blocked.error.is_empty() and empty_blocked.progress_revision == 1, "Read-only restoration clears its error and refreshes committed progress")
	check.call(FileAccess.get_file_as_string(broken_path) == repaired_bytes, "Restoration without pending takes does not rewrite the repaired archive")
	if engine != null:
		var owner = ClassDB.instantiate("DrumxEngine")
		var contender = ClassDB.instantiate("DrumxEngine")
		var archive := ProjectSettings.globalize_path(prefix + "-drüm-拍.json")
		var independent := ProjectSettings.globalize_path(prefix + "-independent.json")
		check.call(owner.acquire_progress_lock(archive), "Native bridge acquires an isolated Unicode archive")
		check.call(owner.snapshot().get("progress_owned", false) and str(owner.snapshot().get("progress_archive_path", "")).replace("\\", "/") == archive.replace("\\", "/"), "Native bridge exposes actual archive ownership")
		check.call(not contender.acquire_progress_lock(archive) and not contender.snapshot().get("progress_owned", true) and not str(contender.snapshot().get("progress_lock_error", "")).is_empty(), "Second engine cannot claim the same archive and reports why")
		check.call(owner.acquire_progress_lock(archive), "Repeated same-owner claim is idempotent")
		check.call(contender.acquire_progress_lock(independent), "Different archive can be owned independently")
		owner = null
		check.call(contender.acquire_progress_lock(archive), "Native owner destruction releases the operating-system lock")
		contender = null
		for lock_path in [archive + ".lock", independent + ".lock"]:
			check.call(DirAccess.remove_absolute(lock_path) == OK, "Isolated lock fixture is released for cleanup")
	for path in [target, target + ".tmp", broken_path, broken_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result
