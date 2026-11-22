extends SceneTree

## Regression probe for the desktop simulation. This deliberately tests the
## player-facing control contract instead of only checking script parsing.

const Simulation = preload("res://scripts/simulation.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _test_determinism():
		return
	if not _test_pause_and_speed():
		return
	if not _test_wave_progression():
		return
	if not _test_heat_disconnect_events():
		return
	print("QA_SMOKE_OK determinism=pause-speed-wave-effects")
	quit(0)

func _new_simulation(seed_value: int):
	var simulation = Simulation.new(seed_value)
	var scanner: String = simulation.add_module("scanner", Vector2i(1, 2))
	var cannon: String = simulation.add_module("railgun", Vector2i(4, 2))
	var router: String = simulation.add_module("router", Vector2i(2, 2))
	simulation.connect_modules(scanner, router, "signal")
	simulation.connect_modules(router, cannon, "signal")
	simulation.add_rule(cannon, "enemy_in_range", "always", "fire")
	return simulation

func _test_determinism() -> bool:
	var first = _new_simulation(2026)
	var second = _new_simulation(2026)
	if not first.start_battle() or not second.start_battle():
		return _fail("determinism setup could not start battle")
	first.advance(30.0)
	second.advance(30.0)
	if first.replay_signature() != second.replay_signature():
		return _fail("same seed produced different replay signatures")
	return true

func _test_pause_and_speed() -> bool:
	var simulation = _new_simulation(77)
	if not simulation.start_battle():
		return _fail("pause setup could not start battle")
	simulation.advance(1.0)
	var tick_before_pause: int = simulation.tick_count
	simulation.set_paused(true)
	simulation.advance(2.0)
	if simulation.tick_count != tick_before_pause:
		return _fail("paused simulation advanced ticks")
	simulation.set_paused(false)
	simulation.set_speed(4.0)
	simulation.advance(1.0)
	if simulation.tick_count <= tick_before_pause:
		return _fail("4x simulation did not advance")
	return true

func _test_wave_progression() -> bool:
	var simulation = _new_simulation(9090)
	if not simulation.start_battle():
		return _fail("wave setup could not start battle")
	for _index in 200:
		simulation.advance(0.1)
	if simulation.current_wave < 2:
		return _fail("simulation did not reach the second wave")
	return true

func _test_heat_disconnect_events() -> bool:
	var simulation = _new_simulation(6060)
	var cannon_id := ""
	for module_id in simulation.modules.keys():
		var module: Dictionary = simulation.modules[module_id]
		if str(module.get("kind", "")) == "railgun":
			cannon_id = str(module_id)
			break
	if cannon_id.is_empty():
		return _fail("heat setup could not find railgun")
	simulation.modules[cannon_id].heat_rate = 100
	if not simulation.start_battle():
		return _fail("heat setup could not start battle")
	for _index in 80:
		simulation.advance(0.1)
	var saw_overheat := false
	var saw_disconnect := false
	for event in simulation.get_event_log():
		var kind := str(event.get("kind", ""))
		saw_overheat = saw_overheat or kind == "overheat"
		saw_disconnect = saw_disconnect or kind == "disconnect"
	if not saw_overheat or not saw_disconnect:
		return _fail("overheat did not emit overheat and disconnect events")
	return true

func _fail(message: String) -> bool:
	push_error("QA_SMOKE_FAILED: " + message)
	quit(1)
	return false
