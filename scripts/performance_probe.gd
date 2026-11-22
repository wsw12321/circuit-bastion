extends SceneTree

const Simulation = preload("res://scripts/simulation.gd")
const STEPS := 1000
const DEFAULT_BUDGET_MS := 5000.0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var simulation = Simulation.new(2026)
    var scanner := simulation.add_module("scanner", Vector2i(1, 2))
    var router := simulation.add_module("router", Vector2i(2, 2))
    var cannon := simulation.add_module("pulse_cannon", Vector2i(3, 2))
    simulation.connect_modules(scanner, router, "signal")
    simulation.connect_modules(router, cannon, "signal")
    simulation.add_rule(cannon, "enemy_in_range", "always", "fire")
    if not simulation.start_battle():
        _fail("benchmark simulation did not start")
        return
    var started_at := Time.get_ticks_usec()
    for _index in STEPS:
        simulation.advance(0.1)
    var elapsed_ms := float(Time.get_ticks_usec() - started_at) / 1000.0
    var budget_text := OS.get_environment("PERF_BUDGET_MS")
    var budget_ms := DEFAULT_BUDGET_MS if budget_text.is_empty() else float(budget_text)
    if elapsed_ms > budget_ms:
        _fail("benchmark exceeded %.1f ms with %.1f ms" % [budget_ms, elapsed_ms])
        return
    if simulation.event_log.size() > 512:
        _fail("event log exceeded the 512 record budget")
        return
    print("PERF_OK steps=%d elapsed_ms=%.1f budget_ms=%.1f events=%d" % [STEPS, elapsed_ms, budget_ms, simulation.event_log.size()])
    quit(0)

func _fail(message: String) -> void:
    push_error("PERF_FAILED: " + message)
    quit(1)
