extends SceneTree

## Headless-safe probe for the procedural audio feedback bus.
## It checks that every semantic cue is emitted even when playback is skipped.

const AudioFeedbackBus = preload("res://scripts/audio_feedback.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var bus := AudioFeedbackBus.new()
	root.add_child(bus)
	await process_frame
	var received: Array[String] = []
	bus.feedback_emitted.connect(func(kind: String, _payload: Dictionary) -> void:
		received.append(kind)
	)
	bus.emit_feedback("button", {"command": "pause"})
	bus.emit_feedback("deploy", {"module": "pulse_cannon"})
	bus.emit_feedback("attack", {"target": "E001"})
	bus.emit_feedback("alert", {"source": "E001"})
	bus.emit_feedback("victory", {})
	bus.emit_feedback("defeat", {})
	bus.emit_simulation_event({"kind": "module", "source": "M01"})
	bus.emit_simulation_event({"kind": "action", "source": "M01"})
	bus.emit_simulation_event({"kind": "breach", "source": "E001"})
	bus.emit_simulation_event({"kind": "victory"})
	bus.emit_simulation_event({"kind": "defeat"})
	if received.size() != 11:
		_fail("expected 11 feedback events, got %d" % received.size())
		return
	if bus.history().size() != 11:
		_fail("history did not retain emitted events")
		return
	if not bus.history()[0].has("played"):
		_fail("history entry missing playback state")
		return
	print("AUDIO_FEEDBACK_OK available=%s events=%d" % [bus.is_audio_available(), received.size()])
	quit(0)

func _fail(message: String) -> void:
	push_error("AUDIO_FEEDBACK_FAILED: " + message)
	quit(1)
