extends SceneTree

## Headless-safe probe for the procedural audio feedback bus.
## It checks semantic cues, priority metadata, rhythm sequencing, settings, and
## playback skipping when no audio device is available.

const AudioFeedbackBus = preload("res://scripts/audio_feedback.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var bus := AudioFeedbackBus.new()
	root.add_child(bus)
	await process_frame
	var generated = bus._stream_for("attack")
	if generated == null:
		_fail("procedural attack stream was not generated")
		return
	var replacement_stream := AudioStreamWAV.new()
	bus.set_resource_slot("button", replacement_stream)
	if bus._stream_for("button") != replacement_stream:
		_fail("resource slot did not override generated button stream")
		return
	if bus.priority_for("defeat") <= bus.priority_for("attack"):
		_fail("defeat priority must exceed attack priority")
		return
	bus.set_priority("attack", 80)
	if bus.priority_for("attack") != 80:
		_fail("priority override was not applied")
		return
	bus.set_priority("attack", 40)
	bus.set_volume(0.75)
	bus.set_mobile_audio_volume(0.5)
	bus.set_mobile_audio_muted(true)
	var settings := bus.audio_settings()
	if absf(float(settings.get("volume", 0.0)) - 0.75) > 0.001:
		_fail("master volume setting was not retained")
		return
	if absf(float(settings.get("mobile_volume", 0.0)) - 0.5) > 0.001:
		_fail("mobile volume setting was not retained")
		return
	if not bool(settings.get("mobile_muted", false)):
		_fail("mobile mute setting was not retained")
		return
	bus.set_mobile_audio_muted(false)
	bus.set_mobile_audio_volume(1.0)
	var received: Array[String] = []
	bus.feedback_emitted.connect(func(kind: String, _payload: Dictionary) -> void:
		received.append(kind)
	)
	bus.emit_feedback("button", {"command": "pause"})
	bus.emit_feedback("deploy", {"module": "pulse_cannon"})
	bus.emit_feedback("attack", {"target": "E001", "tick": 1})
	bus.emit_feedback("attack", {"target": "E002", "tick": 2})
	var attack_rhythm: Dictionary = bus.history()[0].get("rhythm", {})
	if int(attack_rhythm.get("step", -1)) != 1:
		_fail("attack rhythm did not advance to the second step")
		return
	bus.emit_feedback("alert", {"source": "E001"})
	bus.emit_feedback("victory", {})
	bus.emit_feedback("defeat", {})
	bus.emit_simulation_event({"kind": "module", "source": "M01"})
	bus.emit_simulation_event({"kind": "action", "source": "M01"})
	bus.emit_simulation_event({"kind": "breach", "source": "E001"})
	bus.emit_simulation_event({"kind": "victory"})
	bus.emit_simulation_event({"kind": "defeat"})
	if received.size() != 12:
		_fail("expected 12 feedback events, got %d" % received.size())
		return
	if bus.history().size() != 12:
		_fail("history did not retain emitted events")
		return
	var final_record: Dictionary = bus.history()[0]
	if int(final_record.get("priority", 0)) != bus.priority_for("defeat"):
		_fail("defeat priority metadata was not recorded")
		return
	if not bool(final_record.get("rhythm", {}).get("accent", false)):
		_fail("terminal cue did not receive a rhythm accent")
		return
	print("AUDIO_FEEDBACK_OK available=%s events=%d settings=%s" % [bus.is_audio_available(), received.size(), bus.audio_settings()])
	quit(0)

func _fail(message: String) -> void:
	push_error("AUDIO_FEEDBACK_FAILED: " + message)
	quit(1)
