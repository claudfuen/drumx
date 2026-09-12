extends SceneTree

const Contract = preload("res://scripts/pulse_tempo_contract.gd")

func _initialize() -> void:
	var engine: Object = ClassDB.instantiate("DrumxEngine") if ClassDB.class_exists("DrumxEngine") else null
	var result := Contract.run_checks(engine)
	for failure in result.failures:
		printerr("DRUMX_PULSE_BINDING_FAILED: " + str(failure))
	if result.failures.is_empty():
		print("DRUMX_PULSE_BINDING_OK %d checks" % int(result.checks))
	quit(0 if result.failures.is_empty() else 1)
