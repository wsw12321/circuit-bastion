extends SceneTree

const Catalog = preload("res://scripts/content_catalog.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	_assert(catalog.module_spec("pulse_cannon").get("damage", 0) == 18, "module content missing")
	_assert(catalog.enemy_spec("boss").get("label", "") == "熔断主宰", "boss content missing")
	_assert(catalog.wave_spec(10).get("boss", "") == "boss", "wave content missing")
	_assert(catalog.content_signature() != "", "content signature missing")
	print("CONTENT_OK signature=%s modules=%d enemies=%d waves=%d" % [catalog.content_signature(), catalog.modules.size(), catalog.enemies.size(), catalog.waves.size()])
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("CONTENT_ASSERT_FAILED: " + message)
		quit(1)
