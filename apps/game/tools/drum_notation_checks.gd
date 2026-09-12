extends SceneTree
const Contract = preload("res://scripts/notation_contract.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var result := Contract.new().run_checks(root)
	print("DRUM_NOTATION_CHECKS %d checks; failures=%d" % [result.checks, result.failures])
	quit(1 if result.failures else 0)
