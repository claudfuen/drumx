extends SceneTree
const Contract = preload("res://scripts/visual_contract.gd")

func _initialize() -> void:
	var script = load("res://scripts/practice_stage.gd")
	if script == null or not script.can_instantiate():
		printerr("DRUMX_VISUAL_PARITY_FAILED: practice stage cannot be instantiated.")
		quit(1)
		return
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://data/visual-baseline.json"))
	if not fixture is Dictionary:
		printerr("DRUMX_VISUAL_PARITY_FAILED: native fixture cannot be read.")
		quit(1)
		return
	var stage: Control = script.new()
	root.add_child(stage)
	var result := Contract.compare_stage(stage, fixture)
	stage.free()
	for failure in result.failures:
		printerr("DRUMX_VISUAL_PARITY_FAILED: " + failure)
	if not result.failures.is_empty():
		quit(1)
		return
	print("DRUMX_VISUAL_PARITY_OK %d original Swift projection/shape/fade checks" % int(result.checks))
	quit(0)
