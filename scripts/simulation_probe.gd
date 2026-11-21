extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")

func _initialize() -> void:
	var first = _build_run(2026)
	var second = _build_run(2026)
	_assert(first.replay_signature() == second.replay_signature(), "same seed must produce same replay")
	_assert(first.current_wave >= 1, "battle should start a wave")
	_assert(first.get_event_log().size() > 0, "event trace must contain records")
	print("SIMULATION_OK signature=%s events=%d wave=%d integrity=%d" % [first.replay_signature(), first.get_event_log().size(), first.current_wave, first.base_integrity])
	quit(0)

func _build_run(seed_value: int):
	var simulation = Simulation.new(seed_value)
	var scanner := simulation.add_module("scanner", Vector2i(1, 2))
	var cannon := simulation.add_module("pulse_cannon", Vector2i(3, 2))
	var router := simulation.add_module("router", Vector2i(2, 2))
	simulation.connect_modules(scanner, router, "signal")
	simulation.connect_modules(router, cannon, "signal")
	simulation.add_rule(cannon, "enemy_in_range", "always", "fire")
	simulation.start_battle()
	for _index in 500:
		simulation.advance(0.1)
	return simulation

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("SIMULATION_ASSERT_FAILED: " + message)
		quit(1)
