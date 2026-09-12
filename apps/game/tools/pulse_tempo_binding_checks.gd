extends SceneTree

# Release-safe binding checks. This script never starts audio, opens a MIDI
# source, loads a chart, writes progress, or creates a visible window.
static func run_checks(engine: Object) -> Dictionary:
	var result := {"checks": 0, "failures": []}
	var check := func(ok: bool, label: String) -> void:
		result.checks += 1
		if not ok: result.failures.append(label)
	if engine == null or not engine.has_method("evaluate_pulse_tempo") or not engine.has_method("pulse_tempo_plan"):
		check.call(false, "Shared pulse tempo methods are registered")
		return result
	var plan: Dictionary = engine.pulse_tempo_plan()
	check.call(plan.get("ok", false) and plan.get("policy_version") == 1, "Versioned policy is explicit")
	check.call(plan.get("lesson") == "find-the-pulse" and plan.get("version") == "find-the-pulse-v1", "Policy belongs to the exact pulse chart")
	check.call(plan.get("start_bpm") == 60 and plan.get("checkpoint_bpm") == 72 and plan.get("step_bpm") == 6 and plan.get("phrase_bars") == 16, "Authored tempo plan constants")
	check.call(plan.get("stretch_bpms") == [84, 96] and plan.get("required_qualifying") == 2 and plan.get("comparable_window") == 3, "Stretch goals and repeatability are explicit")
	var context := _context()
	var first := _attempt("take-one")
	var second := _attempt("take-two")
	var output: Dictionary = engine.evaluate_pulse_tempo([], context)
	check.call(output.get("ok", false) and not output.get("current_earned", true), "Empty history grants no evidence")
	check.call(output.get("next_bpm") == 60 and output.get("next_bars") == 16 and output.get("next_guidance") == 0 and output.get("next_live_feedback") == true, "Begin intent includes every practice setting")
	output = engine.evaluate_pulse_tempo([first], context)
	check.call(output.get("recent_qualifying") == 1 and not output.get("current_earned", true), "One strong phrase does not establish repeated evidence")
	check.call(output.get("next_bpm") == 66 and plan.get("advance_qualifying") == 1, "One strong phrase may suggest a step below the checkpoint")
	output = engine.evaluate_pulse_tempo([first, second], context)
	check.call(output.get("ok", false) and output.get("current_earned", false) and output.get("next_bpm") == 66, "Two distinct strong takes earn the next tempo")
	output = engine.evaluate_pulse_tempo([first, first], context)
	check.call(output.get("recent_completed") == 1 and not output.get("current_earned", true), "Duplicate full IDs count once")
	var correction := second.duplicate(true)
	correction.on_time = 0
	output = engine.evaluate_pulse_tempo([first, second, correction], context)
	check.call(output.get("ok", false) and not output.get("current_earned", true), "Latest correction removes earlier successful evidence")
	output = engine.evaluate_pulse_tempo([first, correction, second], context)
	check.call(output.get("current_earned", false), "A corrected delayed score can restore evidence")
	output = engine.evaluate_pulse_tempo([first, second, {"id": second.id, "lesson": second.lesson, "version": second.version, "legacy": true}], context)
	check.call(output.get("ok", false) and output.get("legacy_count") == 1 and not output.get("current_earned", true), "Legacy correction never exposes the old same-ID score")
	var prefix := "full-untruncated-identity-".repeat(10)
	var long_first := first.duplicate(true)
	var long_second := second.duplicate(true)
	long_first.id = prefix + "A"
	long_second.id = prefix + "B"
	output = engine.evaluate_pulse_tempo([long_first, long_second], context)
	check.call(output.get("current_earned", false), "Full long IDs are distinct beyond a shared prefix")
	var separate := second.duplicate(true)
	separate.conditions_key += "another-complete-source-or-mapping"
	output = engine.evaluate_pulse_tempo([first, separate], context)
	check.call(not output.get("current_earned", true) and output.get("recent_completed") == 1, "Different complete condition keys never pool")
	separate = second.duplicate(true)
	separate.monitoring = true
	output = engine.evaluate_pulse_tempo([first, separate], context)
	check.call(not output.get("current_earned", true), "Monitoring change cannot pool under a mistakenly reused key")
	separate = second.duplicate(true)
	separate.calibration_ms = 0.25
	output = engine.evaluate_pulse_tempo([first, separate], context)
	check.call(not output.get("current_earned", true), "Fractional calibration remains exact")
	for policy in [0, 2]:
		var old_first := first.duplicate(true)
		var old_second := second.duplicate(true)
		old_first.policy_version = policy
		old_second.policy_version = policy
		output = engine.evaluate_pulse_tempo([old_first, old_second], context)
		check.call(output.get("ok", false) and not output.get("current_earned", true), "Policy %d is ineligible without backfill" % policy)
	var interrupted := second.duplicate(true)
	interrupted.uninterrupted = false
	output = engine.evaluate_pulse_tempo([first, interrupted], context)
	check.call(output.get("ok", false) and not output.get("current_earned", true), "Interrupted phrase cannot earn progression")
	var partial := second.duplicate(true)
	partial.naturally_completed = false
	partial.matched = 10
	partial.on_time = 10
	output = engine.evaluate_pulse_tempo([first, partial], context)
	check.call(output.get("ok", false) and not output.get("current_earned", true), "Unresolved future targets in a partial take do not count")
	var checkpoint := _context()
	checkpoint.bpm = 72
	for mode in [0, 1, 2]:
		checkpoint.guidance = mode
		checkpoint.live_feedback = mode != 2
		var a := _attempt("checkpoint-a", checkpoint)
		var b := _attempt("checkpoint-b", checkpoint)
		output = engine.evaluate_pulse_tempo([a, b], checkpoint)
		var field: String = ["checkpoint_earned", "hidden_earned", "recall_earned"][mode]
		check.call(output.get("ok", false) and output.get(field, false), "Separate checkpoint evidence: " + field)
	var recall_live := checkpoint.duplicate(true)
	recall_live.live_feedback = true
	output = engine.evaluate_pulse_tempo([_attempt("r1", recall_live), _attempt("r2", recall_live)], recall_live)
	check.call(not output.get("recall_earned", true), "Live feedback cannot grant strict recall evidence")
	var parsed: Variant = JSON.parse_string(JSON.stringify([first, second]))
	output = engine.evaluate_pulse_tempo(parsed, JSON.parse_string(JSON.stringify(context)))
	check.call(output.get("current_earned", false), "JSON whole-number floats preserve valid evidence")
	var bad_current := context.duplicate(true)
	bad_current.version = "find-the-pulse-v2"
	check.call(not engine.evaluate_pulse_tempo([], bad_current).get("ok", true), "Wrong current lesson revision is rejected")
	bad_current = context.duplicate(true)
	bad_current.policy_version = 2
	check.call(not engine.evaluate_pulse_tempo([], bad_current).get("ok", true), "Unknown current policy is rejected")
	check.call(not engine.evaluate_pulse_tempo(["not a record"], context).get("ok", true), "Non-dictionary attempt is rejected")
	var malformed: Array = []
	var missing := second.duplicate(true)
	missing.erase("live_feedback")
	malformed.append(missing)
	var fraction := second.duplicate(true)
	fraction.matched = 63.5
	malformed.append(fraction)
	var nonfinite := second.duplicate(true)
	nonfinite.bpm = NAN
	malformed.append(nonfinite)
	var wrong_version := second.duplicate(true)
	wrong_version.version = "another-chart-v1"
	malformed.append(wrong_version)
	var impossible := second.duplicate(true)
	impossible.on_time = 65
	malformed.append(impossible)
	for index in range(malformed.size()):
		output = engine.evaluate_pulse_tempo([first, second, malformed[index]], context)
		check.call(not output.get("ok", true) and output.get("error_index") == 2 and not str(output.get("error", "")).is_empty(), "Malformed late correction %d fails explicitly" % index)
	return result

static func _context() -> Dictionary:
	return {"lesson": "find-the-pulse", "version": "find-the-pulse-v1", "conditions_key": "source=keyboard;mapping=[[42,44,46],[38,40],[36]];monitoring=false;calibration=0", "policy_version": 1, "bpm": 60, "bars": 16, "guidance": 0, "live_feedback": true, "monitoring": false, "calibration_ms": 0.0}

static func _attempt(identifier: String, context: Dictionary = {}) -> Dictionary:
	var value: Dictionary = (_context() if context.is_empty() else context).duplicate(true)
	value.merge({"id": identifier, "expected": 64, "matched": 64, "on_time": 64, "missed": 0, "extra": 0, "naturally_completed": true, "uninterrupted": true})
	return value

func _initialize() -> void:
	var engine: Object = ClassDB.instantiate("DrumxEngine") if ClassDB.class_exists("DrumxEngine") else null
	var result := run_checks(engine)
	for failure in result.failures:
		printerr("DRUMX_PULSE_BINDING_FAILED: " + str(failure))
	if result.failures.is_empty():
		print("DRUMX_PULSE_BINDING_OK %d checks" % int(result.checks))
	quit(0 if result.failures.is_empty() else 1)
