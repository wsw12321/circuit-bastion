extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")

func _initialize() -> void:
	var simulation = Simulation.new(5150)
	_assert(simulation.preview_placement("pulse_cannon", Vector2i(0, 3)).valid == false, "entry cell must be blocked")
	var preview: Dictionary = simulation.preview_build("pulse_cannon", Vector2i(2, 2), 1)
	_assert(bool(preview.get("valid", false)), "empty cell should be buildable")
	var starting_charge: int = simulation.charge
	var module_id: String = simulation.build_module("pulse_cannon", Vector2i(2, 2), 1)
	_assert(not module_id.is_empty(), "build should create a module")
	_assert(simulation.charge == starting_charge - simulation.module_cost("pulse_cannon"), "build should deduct cost")
	_assert(not bool(simulation.preview_build("router", Vector2i(2, 2)).get("valid", true)), "occupied cell must be blocked")
	_assert(simulation.move_module(module_id, Vector2i(3, 2)), "module should move to an empty cell")
	_assert(simulation.set_module_rotation(module_id, 3), "module rotation should be settable")
	_assert(simulation.upgrade_module(module_id, "overclock"), "module upgrade should compile")
	var refund: int = simulation.sell_module(module_id)
	_assert(refund > 0 and not simulation.modules.has(module_id), "selling should refund and remove module")

	var first_inventory: Array = simulation.get_shop_inventory()
	_assert(first_inventory.size() == 4, "shop should expose four deterministic slots")
	_assert(simulation.refresh_shop(true), "forced refresh should succeed")
	var second_inventory: Array = simulation.get_shop_inventory()
	_assert(second_inventory.size() == 4 and first_inventory != second_inventory, "refresh should rotate inventory")
	var purchased := simulation.buy_shop_slot(0, true)
	_assert(purchased and simulation.get_bench().size() == 1, "shop purchase should enter bench")
	var bench_kind: String = str(simulation.get_bench()[0].get("kind", ""))
	var deployed: String = simulation.deploy_bench_item(0, Vector2i(4, 4), 2)
	_assert(not deployed.is_empty() and bench_kind == str(simulation.modules[deployed].get("kind", "")), "bench item should deploy once")

	_assert(simulation.start_battle(), "battle should start with deployed module")
	var tick_before: int = simulation.tick_count
	simulation.set_paused(true)
	simulation.advance(1.0)
	_assert(simulation.tick_count == tick_before, "pause should freeze the simulation")
	_assert(simulation.retry_battle(), "retry should reset combat without clearing build")
	var diagnostics: Dictionary = simulation.get_diagnostics()
	_assert(diagnostics.has("warnings") and diagnostics.has("phase"), "diagnostics should expose warnings and phase")
	print("P1_SMOKE_OK build=move-rotate-sell shop=refresh-buy-deploy upgrade=retry")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("P1_SMOKE_FAILED: " + message)
		quit(1)
