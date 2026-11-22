extends Node
## Audio feedback bus for the Godot vertical slice.
##
## The bus always records and emits feedback events. Playback is best-effort:
## headless runs and environments without an audio bus remain fully functional.
## Call set_resource_slot() to replace a generated cue with an imported stream.

signal feedback_emitted(kind: String, payload: Dictionary)
signal playback_skipped(kind: String, reason: String)

const MIX_RATE := 22050
const MAX_HISTORY := 64
const CUE_DURATION := 0.095

var resource_slots: Dictionary = {}
var generated_streams: Dictionary = {}
var recent_feedback: Array[Dictionary] = []
var _audio_enabled := false
var _ui_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_enabled = _detect_audio()
	if not _audio_enabled:
		return
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UiPlayer"
	add_child(_ui_player)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SfxPlayer"
	add_child(_sfx_player)

func is_audio_available() -> bool:
	return _audio_enabled

func set_enabled(value: bool) -> void:
	_audio_enabled = value
	if value and _ui_player == null:
		_ready()

func set_resource_slot(kind: String, stream: AudioStream) -> void:
	var normalized := _normalize_kind(kind)
	if stream == null:
		resource_slots.erase(normalized)
	else:
		resource_slots[normalized] = stream
	generated_streams.erase(normalized)

func emit_feedback(kind: String, payload: Dictionary = {}) -> void:
	var normalized := _normalize_kind(kind)
	var copied_payload := payload.duplicate(true)
	recent_feedback.push_front({
		"kind": normalized,
		"payload": copied_payload,
		"played": _audio_enabled,
	})
	if recent_feedback.size() > MAX_HISTORY:
		recent_feedback.pop_back()
	feedback_emitted.emit(normalized, copied_payload)
	if not _audio_enabled:
		playback_skipped.emit(normalized, "audio-unavailable")
		return
	var stream := _stream_for(normalized)
	if stream == null:
		playback_skipped.emit(normalized, "stream-unavailable")
		return
	var player := _ui_player if normalized == "button" else _sfx_player
	if player == null:
		playback_skipped.emit(normalized, "player-unavailable")
		return
	player.stream = stream
	player.volume_db = -8.0 if normalized == "button" else -4.0
	player.play()

func emit_simulation_event(event: Dictionary) -> void:
	var event_kind := str(event.get("kind", ""))
	match event_kind:
		"module":
			emit_feedback("deploy", event)
		"action", "enemy_destroyed":
			emit_feedback("attack", event)
		"breach", "warning":
			emit_feedback("alert", event)
		"victory":
			emit_feedback("victory", event)
		"defeat":
			emit_feedback("defeat", event)
		_:
			return

func history() -> Array[Dictionary]:
	return recent_feedback.duplicate(true)

func _detect_audio() -> bool:
	if OS.has_feature("headless"):
		return false
	if DisplayServer.get_name().to_lower() == "headless":
		return false
	return AudioServer.get_bus_count() > 0

func _normalize_kind(kind: String) -> String:
	var normalized := kind.strip_edges().to_lower()
	return normalized if normalized in ["button", "deploy", "attack", "alert", "victory", "defeat"] else "button"

func _stream_for(kind: String) -> AudioStream:
	var selected = resource_slots.get(kind)
	if selected is AudioStream:
		return selected
	if generated_streams.has(kind):
		return generated_streams[kind]
	var stream := _generate_stream(kind)
	generated_streams[kind] = stream
	return stream

func _generate_stream(kind: String) -> AudioStreamWAV:
	var frequencies := {
		"button": 520.0,
		"deploy": 330.0,
		"attack": 760.0,
		"alert": 180.0,
		"victory": 660.0,
		"defeat": 120.0,
	}
	var frequency: float = float(frequencies.get(kind, 440.0))
	var sample_count := int(float(MIX_RATE) * CUE_DURATION)
	var data := PackedByteArray()
	data.resize(sample_count)
	for index in sample_count:
		var time := float(index) / float(MIX_RATE)
		var fade_in := clampf(time / 0.008, 0.0, 1.0)
		var fade_out := clampf((CUE_DURATION - time) / 0.024, 0.0, 1.0)
		var envelope := minf(fade_in, fade_out)
		var harmonic := sin(TAU * frequency * time)
		if kind == "victory":
			harmonic = (harmonic + 0.35 * sin(TAU * frequency * 1.5 * time)) / 1.35
		elif kind == "defeat":
			harmonic = (harmonic + 0.3 * sin(TAU * frequency * 0.5 * time)) / 1.3
		data[index] = clampi(int(128.0 + harmonic * envelope * 74.0), 0, 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
