extends RefCounted

const SAVE_PATH = "user://progress-v1.json"
var save_path := SAVE_PATH
var course: Dictionary = {}
var save: Dictionary = {"version": 1, "selected": 0, "read": {}, "attempts": [], "settings": {}}
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
		return
	var parser := JSON.new()
	var parse_status := parser.parse(FileAccess.get_file_as_string(save_path))
	var parsed = parser.data if parse_status == OK else null
	if not valid_save(parsed):
		error = "Saved progress could not be read. Your file has been preserved."
		blocked = true
		return
	save = parsed
	save["settings"] = save.get("settings", {})
	save["selected"] = int(save.get("selected", 0))
	for attempt in save.attempts:
		attempt.settings.bpm = float(attempt.settings.bpm)
		attempt.settings.bars = int(attempt.settings.bars)
		attempt.settings.guidance = int(attempt.settings.guidance)
		attempt.settings.mapping = normalized_mapping(attempt.settings.mapping)
	if save.settings.has("mapping"):
		save.settings.mapping = normalized_mapping(save.settings.mapping)

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
	var needs_reading := index in [3, 7]
	if needs_reading and not bool(save.read.get(course.lessons[index].version, false)):
		return false
	for attempt in save.attempts:
		if attempt.lesson == course.lessons[index].id and attempt.version == course.lessons[index].version:
			if int(attempt.settings.bars) >= 4 and float(attempt.matched) / maxi(1, int(attempt.expected)) >= 0.8:
				return true
	return false

func frontier() -> int:
	for index in range(course.lessons.size()):
		if not cleared(index):
			return index
	return 11

func record(identifier: String, index: int, snapshot: Dictionary, settings: Dictionary) -> bool:
	if not bool(snapshot.get("naturally_completed", false)):
		return false
	var attempt := {"id": identifier, "lesson": course.lessons[index].id, "version": course.lessons[index].version,
		"settings": settings, "points": points(snapshot, true), "best_streak": int(snapshot.get("best_streak", 0)),
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
		return whole(value.get("bpm"), 30, 240) and whole(value.get("bars"), 4, 32) and whole(value.get("guidance"), 0, 2) and value.get("source") is String and valid_mapping(value.get("mapping"))
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
	var identifiers: Array = []
	for attempt in value.attempts:
		if not valid_attempt(attempt) or attempt.id in identifiers:
			return false
		identifiers.append(attempt.id)
	for key in value.read:
		if not key is String or not value.read[key] is bool:
			return false
	return true
