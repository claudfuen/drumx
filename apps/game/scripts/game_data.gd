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

func load_course() -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/course.json"))
	if not parsed is Dictionary or not parsed.get("lessons") is Array:
		return false
	course = parsed
	return course.lessons.size() == 12

func load_progress() -> void:
	if not FileAccess.file_exists(save_path):
		ensure_tempo_coach(false)
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
	for attempt in save.attempts:
		attempt.settings.bpm = float(attempt.settings.bpm)
		attempt.settings.bars = int(attempt.settings.bars)
		attempt.settings.guidance = int(attempt.settings.guidance)
		attempt.settings.mapping = normalized_mapping(attempt.settings.mapping)
		if attempt.settings.has("tempo_policy"):
			attempt.settings.tempo_policy = int(attempt.settings.tempo_policy)
			attempt.settings.calibration_ms = int(attempt.settings.calibration_ms)
	if save.settings.has("mapping"):
		save.settings.mapping = normalized_mapping(save.settings.mapping)
	ensure_tempo_coach(true)

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
	var identifier: String = course.lessons[index].id
	for attempt in save.attempts:
		if attempt.get("lesson") != identifier or attempt.get("version") != course.lessons[index].version:
			continue
		if not settings.is_empty() and attempt.get("settings") != settings:
			continue
		if result.is_empty() or int(attempt.get("points", 0)) > int(result.get("points", 0)):
			result = attempt
	return result

func cleared(index: int) -> bool:
	if index == 0:
		return pulse_checkpoint_earned()
	return legacy_cleared(index)

func legacy_cleared(index: int) -> bool:
	var needs_reading := index in [3, 7]
	if needs_reading and not bool(save.read.get(course.lessons[index].version, false)):
		return false
	for attempt in save.attempts:
		if attempt.lesson == course.lessons[index].id and attempt.version == course.lessons[index].version:
			if int(attempt.settings.bars) >= 4 and float(attempt.matched) / maxi(1, int(attempt.expected)) >= 0.8:
				return true
	return false

func frontier() -> int:
	for index in range(int(save.get("tempo_coach", {}).get("legacy_frontier", 0)), course.lessons.size()):
		if not cleared(index):
			return index
	return 11

func record(identifier: String, index: int, snapshot: Dictionary, settings: Dictionary) -> bool:
	if not bool(snapshot.get("naturally_completed", false)):
		return false
	var attempt := {"id": identifier, "lesson": course.lessons[index].id, "version": course.lessons[index].version,
		"settings": settings.duplicate(true), "points": points(snapshot, true), "best_streak": int(snapshot.get("best_streak", 0)),
		"matched": int(snapshot.get("matched", 0)), "on_time": int(snapshot.get("on_time", 0)),
		"missed": int(snapshot.get("missed", 0)), "extra": int(snapshot.get("extra", 0)), "expected": int(snapshot.get("expected", 0))}
	if not valid_attempt(attempt):
		error = "The completed take contained invalid score data and was not saved."
		return false
	var prior: Dictionary = save.duplicate(true)
	var replaced := false
	for i in range(save.attempts.size()):
		if save.attempts[i].get("id") == identifier:
			if save.attempts[i] == attempt:
				return true
			save.attempts[i] = attempt
			replaced = true
			break
	if not replaced:
		save.attempts.append(attempt)
	if not persist():
		save = prior
		return false
	progress_revision += 1
	return true

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
		if value.has("tempo_policy"):
			if not whole(value.tempo_policy, 1, 1000000) or not value.get("monitoring") is bool or not value.get("live_feedback") is bool or not whole(value.get("calibration_ms"), -500, 500):
				return false
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
	return int(value.points) == points(value, true)

func valid_save(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("attempts") is Array or not value.get("read") is Dictionary or not whole(value.get("selected", 0), 0, 11) or not valid_settings(value.get("settings", {}), false):
		return false
	if value.has("tempo_coach") and not valid_tempo_coach(value.tempo_coach):
		return false
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
		while prior_frontier < 11 and legacy_cleared(prior_frontier): prior_frontier += 1
		prior_frontier = maxi(prior_frontier, int(save.get("selected", 0)))
		for attempt in save.attempts:
			if attempt.lesson == "find-the-pulse" and attempt.version == "find-the-pulse-v1":
				for key in free: free[key] = attempt.settings[key]
	save.tempo_coach = {"version": 1, "legacy_frontier": prior_frontier,
		"intent": "free" if migrate else "guided", "guided": {"bpm": 60, "bars": 16, "guidance": 0}, "free": free}

static func valid_tempo_coach(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not whole(value.get("legacy_frontier"), 0, 11) or value.get("intent") not in ["guided", "free"]: return false
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
