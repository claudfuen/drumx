extends RefCounted

const SAVE_PATH = "user://progress-v1.json"
var save_path := SAVE_PATH
var course: Dictionary = {}
var save: Dictionary = {"version": 1, "selected": 0, "read": {}, "attempts": [], "settings": {}}
var tempo_engine: Object
var tempo_history_key := ""
var tempo_records: Array = []
var tempo_decisions: Dictionary = {}
var progress_revision := 0
var error := ""
var blocked := false
# Completed evidence remains separate from published progress until an atomic
# write succeeds. A new transport must never replace a failed take's payload.
var pending_attempts: Dictionary = {}

func pending_save_count() -> int:
	return pending_attempts.size()

func pending_save_message() -> String:
	var count := pending_save_count()
	if count == 0: return ""
	return "%d %s waiting to save. Keep Drumx open; saving retries between takes." % [count, "result is" if count == 1 else "results are"]

func load_course() -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/course.json"))
	if not parsed is Dictionary or not parsed.get("lessons") is Array:
		return false
	course = parsed
	return not course.lessons.is_empty() and course.get("chapters") is Array and not course.chapters.is_empty()

func load_progress() -> void:
	if not FileAccess.file_exists(save_path):
		ensure_tempo_coach(false)
		ensure_readiness(false)
		return
	var parser := JSON.new()
	var parse_status := parser.parse(FileAccess.get_file_as_string(save_path))
	var parsed = parser.data if parse_status == OK else null
	if not valid_save(parsed):
		error = "Saved progress could not be read. Your file has been preserved."
		blocked = true
		return
	save = parsed
	progress_revision += 1
	save["settings"] = save.get("settings", {})
	save["selected"] = int(save.get("selected", 0))
	for i in range(save.attempts.size()): save.attempts[i] = normalized_attempt(save.attempts[i])
	if save.settings.has("mapping"):
		save.settings.mapping = normalized_mapping(save.settings.mapping)
	ensure_tempo_coach(true)
	ensure_readiness(true)

func persist() -> bool:
	if blocked:
		return false
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		error = "Progress could not be saved on this computer."
		return false
	file.store_string(JSON.stringify(save, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)) != OK:
		error = "Progress could not be saved on this computer."
		return false
	error = ""
	return true

func chart(index: int, bars: int) -> Array:
	var events: Array = []
	for bar in range(bars):
		for authored in course.lessons[index].events:
			var event: Dictionary = authored.duplicate()
			event.beat = float(event.beat) + float(bar * 4)
			event.pad = int(event.pad)
			event.velocity = int(event.get("velocity", 100))
			events.append(event)
	return events

static func points(snapshot: Dictionary, complete: bool) -> int:
	var expected := int(snapshot.get("expected", 0))
	var denominator := expected + int(snapshot.get("extra", 0))
	if denominator <= 0:
		return 0
	var result := floori(10000.0 * float(snapshot.get("on_time", 0)) / denominator)
	return clampi(result, 0, 10000 if complete else 9999)

static func stars(points_value: int, complete: bool) -> int:
	var result := 0
	for threshold in [4000, 6000, 7500, 9000, 10000]:
		if points_value >= threshold:
			result += 1
	return result if complete else mini(4, result)

func best(index: int, settings: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	var comparison := normalized_take_settings(settings) if not settings.is_empty() else {}
	var identifier: String = course.lessons[index].id
	for attempt in save.attempts:
		if attempt.get("lesson") != identifier or attempt.get("version") != course.lessons[index].version:
			continue
		if not comparison.is_empty() and normalized_take_settings(attempt.get("settings", {})) != comparison:
			continue
		if result.is_empty() or int(attempt.get("points", 0)) > int(result.get("points", 0)):
			result = attempt
	return result

func needs_reading(index: int) -> bool:
	return index + 1 < course.lessons.size() and int(course.lessons[index].chapter) != int(course.lessons[index + 1].chapter)

func lesson_requirement(index: int) -> String:
	if index == 0: return "Earn the 72 BPM checkpoint: two steady 16-bar guided takes in three comparable attempts."
	return "Two steady 16-bar guided takes at %d BPM in three comparable attempts. Each instrument: 80%% matched and 70%% on time. Extras: at most 10%%." % int(course.lessons[index].bpm)

func cleared(index: int) -> bool:
	var playing := pulse_checkpoint_earned() if index == 0 else bool(readiness_status(index).checkpoint)
	return playing and (not needs_reading(index) or bool(save.read.get(course.lessons[index].version, false)))

func legacy_cleared(index: int) -> bool:
	if needs_reading(index) and not bool(save.read.get(course.lessons[index].version, false)): return false
	for attempt in save.attempts:
		if attempt.lesson == course.lessons[index].id and attempt.version == course.lessons[index].version and not attempt.settings.has("readiness_policy") and not attempt.settings.has("tempo_policy"):
			if int(attempt.expected) == course.lessons[index].events.size() * int(attempt.settings.bars) and int(attempt.settings.bars) >= 4 and int(attempt.matched) * 5 >= int(attempt.expected) * 4:
				return true
	return false

func frontier() -> int:
	var old_frontier := int(save.get("readiness", {}).get("legacy_frontier", save.get("tempo_coach", {}).get("legacy_frontier", 0)))
	for index in range(old_frontier, course.lessons.size()):
		if not cleared(index): return index
	return maxi(0, course.lessons.size() - 1)

# A checkpoint remains earned after later practice. Each historical window uses
# only the latest three takes at that moment with exactly equal captured settings.
func readiness_status(index: int, settings: Dictionary = {}) -> Dictionary:
	var result := {"passing": 0, "recent": 0, "checkpoint": false, "eligible": false}
	var lesson: Dictionary = course.lessons[index]
	if not settings.is_empty():
		result.eligible = valid_settings(settings, true) and int(settings.get("readiness_policy", 0)) == 1 and int(settings.get("bars", 0)) == 16 and int(settings.get("guidance", -1)) == 0 and float(settings.get("bpm", 0)) == float(lesson.bpm)
	var comparison: Dictionary = normalized_take_settings(settings) if not settings.is_empty() and valid_settings(settings, true) else settings.duplicate(true)
	var groups: Array = []
	var unique: Dictionary = {}
	for stored in save.attempts:
		if stored is Dictionary and stored.get("id") is String: unique[stored.id] = stored
	for stored in unique.values():
		if not valid_attempt(stored): continue
		var attempt: Dictionary = normalized_attempt(stored)
		if attempt.lesson != lesson.id or attempt.version != lesson.version or not valid_attempt(attempt): continue
		var captured: Dictionary = attempt.settings
		if int(captured.get("readiness_policy", 0)) != 1 or int(captured.bars) != 16 or int(captured.guidance) != 0 or float(captured.bpm) != float(lesson.bpm): continue
		if not authored_pads(attempt, index) or (not comparison.is_empty() and captured != comparison): continue
		result.eligible = true
		var target := -1
		for group_index in range(groups.size()):
			if groups[group_index][0].settings == captured: target = group_index; break
		if target < 0: groups.append([attempt])
		else: groups[target].append(attempt)
	for group in groups:
		var window: Array = []
		for attempt in group:
			window.append(attempt)
			if window.size() > 3: window.pop_front()
			var passing := 0
			for prior in window:
				if steady_readiness_take(prior): passing += 1
			if passing >= 2: result.checkpoint = true
		var recent_passing := 0
		for attempt in window:
			if steady_readiness_take(attempt): recent_passing += 1
		if recent_passing > result.passing or (recent_passing == result.passing and window.size() > result.recent):
			result.passing = recent_passing
			result.recent = window.size()
	return result

func authored_pads(attempt: Dictionary, index: int) -> bool:
	if not attempt.has("pads") or attempt.pads.size() != 3: return false
	var expected := [0, 0, 0]
	for event in course.lessons[index].events: expected[int(event.pad)] += int(attempt.settings.bars)
	for pad in range(3):
		if int(attempt.pads[pad].expected) != expected[pad]: return false
	return int(attempt.expected) == course.lessons[index].events.size() * int(attempt.settings.bars)

static func steady_readiness_take(attempt: Dictionary) -> bool:
	if int(attempt.extra) * 10 > int(attempt.expected): return false
	for pad in attempt.pads:
		if int(pad.expected) > 0 and (int(pad.matched) * 100 < int(pad.expected) * 80 or int(pad.on_time) * 100 < int(pad.expected) * 70): return false
	return true

func ensure_readiness(migrate: bool) -> void:
	if save.has("readiness"): return
	var prior := 0
	if migrate:
		prior = int(save.get("tempo_coach", {}).get("legacy_frontier", 0))
		while prior + 1 < course.lessons.size() and legacy_cleared(prior): prior += 1
		prior = maxi(prior, int(save.get("selected", 0)))
		for attempt in save.attempts:
			if attempt.settings.has("readiness_policy"): continue
			for index in range(course.lessons.size()):
				if attempt.lesson == course.lessons[index].id and int(attempt.matched) > 0 and attempt.version == course.lessons[index].version and int(attempt.expected) == course.lessons[index].events.size() * int(attempt.settings.bars):
					prior = maxi(prior, index)
					if index + 1 < course.lessons.size() and legacy_cleared(index): prior = maxi(prior, index + 1)
	save.readiness = {"version": 1, "legacy_frontier": prior}

func record(identifier: String, index: int, snapshot: Dictionary, settings: Dictionary) -> bool:
	if not bool(snapshot.get("naturally_completed", false)):
		return false
	if settings.has("readiness_policy"):
		if not valid_settings(settings, true): return false
		var duration := float(settings.bars) * 240.0 / float(settings.bpm)
		if not is_equal_approx(float(snapshot.get("bpm", -1)), float(settings.bpm)) or int(snapshot.get("guidance", -1)) != int(settings.guidance) or not is_equal_approx(float(snapshot.get("duration_seconds", -1)), duration) or not is_finite(float(snapshot.get("elapsed_seconds", -1))) or float(snapshot.get("elapsed_seconds", -1)) < duration - 0.000001: return false
	var attempt := {"id": identifier, "lesson": course.lessons[index].id, "version": course.lessons[index].version,
		"settings": settings.duplicate(true), "points": points(snapshot, true), "best_streak": int(snapshot.get("best_streak", 0)),
		"matched": int(snapshot.get("matched", 0)), "on_time": int(snapshot.get("on_time", 0)),
		"missed": int(snapshot.get("missed", 0)), "extra": int(snapshot.get("extra", 0)), "expected": int(snapshot.get("expected", 0))}
	if snapshot.has("pads"): attempt.pads = snapshot.pads.duplicate(true)
	if not valid_attempt(attempt) or (settings.has("readiness_policy") and not authored_pads(attempt, index)):
		error = "The completed take contained invalid score data and was not saved."
		return false
	attempt = normalized_attempt(attempt)
	var original: Dictionary = pending_attempts.get(identifier, {})
	if original.is_empty():
		for saved in save.attempts:
			if saved.id == identifier:
				original = saved
				break
	if not original.is_empty():
		if original.settings != attempt.settings or original.lesson != attempt.lesson or original.version != attempt.version:
			error = "The take's captured conditions changed. Its original result has been preserved."
			return false
		if original == attempt and not pending_attempts.has(identifier): return true
	pending_attempts[identifier] = attempt
	return retry_pending()

func retry_pending(restore_archive: bool = false) -> bool:
	if pending_attempts.is_empty() and not (blocked and restore_archive): return true
	if blocked:
		# Only an explicit retry may inspect a repaired archive. Never overwrite
		# the unreadable original or silently replace its surviving history.
		if not restore_archive or not FileAccess.file_exists(save_path): return false
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(save_path)) != OK or not valid_save(parser.data): return false
		var restored: Dictionary = parser.data
		for i in range(restored.attempts.size()): restored.attempts[i] = normalized_attempt(restored.attempts[i])
		for archived in restored.attempts:
			if pending_attempts.has(archived.id):
				var pending: Dictionary = pending_attempts[archived.id]
				if archived.settings != pending.settings or archived.lesson != pending.lesson or archived.version != pending.version:
					error = "The restored archive conflicts with a waiting result. Both have been preserved."
					return false
		save = restored
		blocked = false
		ensure_tempo_coach(true)
		ensure_readiness(true)
		if pending_attempts.is_empty():
			error = ""
			progress_revision += 1
			return true
	var prior: Dictionary = save.duplicate(true)
	for identifier in pending_attempts:
		var replaced := false
		for i in range(save.attempts.size()):
			if save.attempts[i].id == identifier:
				save.attempts[i] = pending_attempts[identifier].duplicate(true)
				replaced = true
				break
		if not replaced: save.attempts.append(pending_attempts[identifier].duplicate(true))
	if not persist():
		save = prior
		return false
	pending_attempts.clear()
	progress_revision += 1
	return true

static func normalized_attempt(value: Dictionary) -> Dictionary:
	var attempt: Dictionary = value.duplicate(true)
	for key in ["points", "matched", "on_time", "missed", "extra", "expected", "best_streak"]:
		attempt[key] = int(attempt[key])
	attempt.settings = normalized_take_settings(attempt.settings)
	if attempt.has("pads"):
		for pad in attempt.pads:
			for key in ["expected", "matched", "missed", "extra", "on_time"]: pad[key] = int(pad[key])
	return attempt

static func normalized_take_settings(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	result.bpm = float(result.bpm)
	result.bars = int(result.bars)
	result.guidance = int(result.guidance)
	result.mapping = normalized_mapping(result.mapping)
	if result.has("tempo_policy"): result.tempo_policy = int(result.tempo_policy)
	if result.has("readiness_policy"):
		result.readiness_policy = int(result.readiness_policy)
		result.calibration_ms = float(result.calibration_ms)
		for aliases in result.mapping: aliases.sort()
	elif result.has("tempo_policy"): result.calibration_ms = int(result.calibration_ms)
	return result

static func whole(value: Variant, minimum: float, maximum: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

static func valid_mapping(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	var seen: Array = []
	for aliases in value:
		if not aliases is Array or aliases.size() > 16:
			return false
		for note in aliases:
			if not whole(note, 0, 127) or int(note) in seen:
				return false
			seen.append(int(note))
	return true

static func normalized_mapping(value: Array) -> Array:
	var result: Array = []
	for aliases in value:
		var notes: Array = []
		for note in aliases:
			notes.append(int(note))
		result.append(notes)
	return result

func valid_settings(value: Variant, take: bool) -> bool:
	if not value is Dictionary:
		return false
	if take:
		if value.has("readiness_policy"):
			if not whole(value.readiness_policy, 1, 1) or value.has("tempo_policy") or not value.get("hand_hints") is bool or not value.get("source") is String or value.source.strip_edges().is_empty(): return false
			if not typeof(value.get("calibration_ms")) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value.calibration_ms)) or absf(float(value.calibration_ms)) > 500: return false
		if value.has("tempo_policy") or value.has("readiness_policy"):
			if not value.get("monitoring") is bool or not value.get("live_feedback") is bool: return false
			if value.has("tempo_policy") and (not whole(value.tempo_policy, 1, 1000000) or not whole(value.get("calibration_ms"), -500, 500)): return false
		return whole(value.get("bpm"), 30, 240) and whole(value.get("bars"), 1, 32) and whole(value.get("guidance"), 0, 2) and value.get("source") is String and valid_mapping(value.get("mapping"))
	if value.has("mapping") and not valid_mapping(value.mapping):
		return false
	if value.has("monitoring") and not value.monitoring is bool:
		return false
	if value.has("volume") and (not (typeof(value.volume) in [TYPE_INT, TYPE_FLOAT]) or not is_finite(float(value.volume)) or float(value.volume) < 0 or float(value.volume) > 1):
		return false
	return true

func valid_attempt(value: Variant) -> bool:
	if not value is Dictionary or not value.get("id") is String or value.id.is_empty() or not value.get("lesson") is String or not value.get("version") is String or not valid_settings(value.get("settings"), true):
		return false
	for key in ["points", "matched", "on_time", "missed", "extra", "expected", "best_streak"]:
		if not whole(value.get(key), 0, 10000000):
			return false
	if int(value.expected) < 1 or int(value.expected) > 4096 or int(value.matched) + int(value.missed) != int(value.expected) or int(value.on_time) > int(value.matched) or int(value.best_streak) > int(value.on_time):
		return false
	if value.has("pads"):
		if not valid_pad_evidence(value.pads, value): return false
	elif value.settings.has("readiness_policy"): return false
	if value.settings.has("readiness_policy") and value.version == "find-the-pulse-v1": return false
	return int(value.points) == points(value, true)

static func valid_pad_evidence(pads: Variant, total: Dictionary) -> bool:
	if not pads is Array or pads.size() != 3: return false
	var sums := {"expected": 0, "matched": 0, "missed": 0, "extra": 0, "on_time": 0}
	for pad in pads:
		if not pad is Dictionary: return false
		for key in sums:
			if not whole(pad.get(key), 0, 10000000 if key == "extra" else 4096): return false
			sums[key] += int(pad[key])
		if int(pad.matched) + int(pad.missed) != int(pad.expected) or int(pad.on_time) > int(pad.matched): return false
	for key in sums:
		if sums[key] != int(total[key]): return false
	return true

func valid_save(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("attempts") is Array or not value.get("read") is Dictionary or not whole(value.get("selected", 0), 0, maxi(0, course.lessons.size() - 1)) or not valid_settings(value.get("settings", {}), false):
		return false
	if value.has("tempo_coach") and not valid_tempo_coach(value.tempo_coach):
		return false
	if value.has("readiness"):
		if not value.readiness is Dictionary or value.readiness.get("version") != 1 or not whole(value.readiness.get("legacy_frontier"), 0, maxi(0, course.lessons.size() - 1)): return false
	var identifiers: Array = []
	for attempt in value.attempts:
		if not valid_attempt(attempt) or attempt.id in identifiers:
			return false
		identifiers.append(attempt.id)
	for key in value.read:
		if not key is String or not value.read[key] is bool:
			return false
	return true

# Tempo policy is evaluated by the same native C function on both platforms.
# The adapter captures provenance before a take and never awards legacy evidence.
func ensure_tempo_coach(migrate: bool = false) -> void:
	if save.has("tempo_coach"): return
	var prior_frontier := 0
	var free := {"bpm": 60, "bars": 16, "guidance": 0}
	if migrate:
		while prior_frontier + 1 < course.lessons.size() and legacy_cleared(prior_frontier): prior_frontier += 1
		prior_frontier = maxi(prior_frontier, int(save.get("selected", 0)))
		for attempt in save.attempts:
			if attempt.lesson == "find-the-pulse" and attempt.version == "find-the-pulse-v1":
				for key in free: free[key] = attempt.settings[key]
	save.tempo_coach = {"version": 1, "legacy_frontier": prior_frontier,
		"intent": "free" if migrate else "guided", "guided": {"bpm": 60, "bars": 16, "guidance": 0}, "free": free}

func valid_tempo_coach(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not whole(value.get("legacy_frontier"), 0, maxi(0, course.lessons.size() - 1)) or value.get("intent") not in ["guided", "free"]: return false
	for mode in ["guided", "free"]:
		var plan = value.get(mode)
		if not plan is Dictionary or not whole(plan.get("bpm"), 30, 240) or not whole(plan.get("bars"), 1, 32) or not whole(plan.get("guidance"), 0, 2): return false
		if mode == "guided" and (int(plan.bars) != 16 or int(plan.bpm) not in [60, 66, 72, 84, 96]): return false
	return true

func pulse_preferences() -> Dictionary:
	ensure_tempo_coach()
	return save.tempo_coach

func remember_pulse(intent: String, bpm: float, bars: int, guidance: int) -> bool:
	var prior: Dictionary = save.duplicate(true)
	ensure_tempo_coach()
	save.tempo_coach.intent = intent
	save.tempo_coach[intent] = {"bpm": bpm, "bars": bars, "guidance": guidance}
	if not valid_tempo_coach(save.tempo_coach) or not persist():
		save = prior
		return false
	return true

static func pulse_context(settings: Dictionary) -> Dictionary:
	var mapping: Array = normalized_mapping(settings.get("mapping", [[42, 44, 46], [38, 40], [35, 36]]))
	for aliases in mapping: aliases.sort()
	var monitor := bool(settings.get("monitoring", true))
	var calibration := int(settings.get("calibration_ms", 0))
	return {"lesson": "find-the-pulse", "version": "find-the-pulse-v1",
		"conditions_key": JSON.stringify([str(settings.get("source", "")), mapping, monitor, calibration]),
		"policy_version": int(settings.get("tempo_policy", 1)), "bpm": float(settings.get("bpm", 60)),
		"bars": int(settings.get("bars", 16)), "guidance": int(settings.get("guidance", 0)),
		"live_feedback": bool(settings.get("live_feedback", int(settings.get("guidance", 0)) != 2)),
		"monitoring": monitor, "calibration_ms": calibration}

func pulse_decision(settings: Dictionary = {}) -> Dictionary:
	if tempo_engine == null: return {"ok": false, "error": "Tempo coaching is unavailable in this build."}
	var history_key := JSON.stringify(save.attempts)
	if history_key != tempo_history_key:
		tempo_history_key = history_key
		tempo_records.clear()
		tempo_decisions.clear()
		for attempt in save.attempts:
			if attempt.lesson != "find-the-pulse" or attempt.version != "find-the-pulse-v1": continue
			if not attempt.settings.has("tempo_policy"):
				tempo_records.append({"id": attempt.id, "lesson": attempt.lesson, "version": attempt.version, "legacy": true})
				continue
			var entry := pulse_context(attempt.settings)
			entry.id = attempt.id
			for key in ["expected", "matched", "on_time", "missed", "extra"]: entry[key] = int(attempt[key])
			entry.naturally_completed = true
			entry.uninterrupted = true
			tempo_records.append(entry)
	var current := pulse_context(settings)
	var key := JSON.stringify(current)
	if not tempo_decisions.has(key):
		tempo_decisions[key] = tempo_engine.evaluate_pulse_tempo(tempo_records, current)
	return tempo_decisions[key]

func pulse_checkpoint_earned() -> bool:
	var seen: Dictionary = {}
	for attempt in save.attempts:
		if attempt.lesson != "find-the-pulse" or attempt.version != "find-the-pulse-v1" or int(attempt.settings.get("tempo_policy", 0)) != 1: continue
		var settings: Dictionary = attempt.settings
		if float(settings.bpm) != 72 or int(settings.guidance) != 0 or not bool(settings.get("live_feedback", false)): continue
		var key: String = pulse_context(settings).conditions_key
		if seen.has(key): continue
		seen[key] = true
		if bool(pulse_decision(settings).get("checkpoint_earned", false)): return true
	return false
