extends Node
## Audio feedback bus for the Godot vertical slice.
##
## The bus always records and emits feedback events. Playback is best-effort:
## headless runs and environments without an audio bus remain fully functional.
## Call set_resource_slot() to replace a generated cue with an imported stream.

signal feedback_emitted(kind: String, payload: Dictionary)
signal playback_skipped(kind: String, reason: String)
signal settings_changed(settings: Dictionary)

const MIX_RATE := 22050
const MAX_HISTORY := 64
const CUE_DURATION := 0.095
const RHYTHM_STEPS := 4
const DEFAULT_PRIORITIES := {
	"button": 10,
	"deploy": 25,
	"attack": 40,
	"alert": 70,
	"victory": 90,
	"defeat": 100,
}

var resource_slots: Dictionary = {}
var generated_streams: Dictionary = {}
var priority_overrides: Dictionary = {}
var recent_feedback: Array[Dictionary] = []
var rhythm_enabled := true
var muted := false
var volume := 1.0
var mobile_muted := false
var mobile_volume := 1.0
var _audio_enabled := false
var _ui_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _active_priorities := {"ui": 0, "sfx": 0}
var _rhythm_kind := ""
var _rhythm_step := -1
var _feedback_sequence := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_enabled = _detect_audio()
	if _audio_enabled:
		_setup_players()

func is_audio_available() -> bool:
	return _audio_enabled

func set_enabled(value: bool) -> void:
	if not value:
		_audio_enabled = false
		_stop_players()
		return
	_audio_enabled = _detect_audio()
	if _audio_enabled:
		_setup_players()
		_apply_player_settings()

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		_stop_players()
	_emit_settings_changed()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	_apply_player_settings()
	_emit_settings_changed()

func set_mobile_audio_muted(value: bool) -> void:
	mobile_muted = value
	if _effective_muted():
		_stop_players()
	_emit_settings_changed()

func set_mobile_audio_volume(value: float) -> void:
	mobile_volume = clampf(value, 0.0, 1.0)
	_apply_player_settings()
	_emit_settings_changed()

func set_mobile_muted(value: bool) -> void:
	set_mobile_audio_muted(value)

func set_mobile_volume(value: float) -> void:
	set_mobile_audio_volume(value)

func audio_settings() -> Dictionary:
	return {
		"muted": muted,
		"volume": volume,
		"mobile_muted": mobile_muted,
		"mobile_volume": mobile_volume,
		"effective_muted": _effective_muted(),
		"effective_volume": _effective_volume(),
	}

func set_rhythm_enabled(value: bool) -> void:
	rhythm_enabled = value
	if not rhythm_enabled:
		_rhythm_kind = ""
		_rhythm_step = -1

func rhythm_state() -> Dictionary:
	return {
		"enabled": rhythm_enabled,
		"group": _rhythm_kind,
		"step": _rhythm_step,
		"accent": _rhythm_kind in ["alert", "victory", "defeat"] or _rhythm_step == 0,
	}

func set_priority(kind: String, priority: int) -> void:
	priority_overrides[_normalize_kind(kind)] = maxi(0, priority)

func priority_for(kind: String) -> int:
	var normalized := _normalize_kind(kind)
	return int(priority_overrides.get(normalized, DEFAULT_PRIORITIES.get(normalized, 10)))

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
	_feedback_sequence += 1
	var priority := priority_for(normalized)
	var rhythm := _next_rhythm(normalized)
	var record := {
		"sequence": _feedback_sequence,
		"kind": normalized,
		"payload": copied_payload,
		"priority": priority,
		"rhythm": rhythm,
		"played": false,
	}
	recent_feedback.push_front(record)
	if recent_feedback.size() > MAX_HISTORY:
		recent_feedback.pop_back()
	feedback_emitted.emit(normalized, copied_payload)
	if not _audio_enabled:
		_skip_latest(normalized, "audio-unavailable")
		return
	if _effective_muted():
		_skip_latest(normalized, "muted")
		return
	if _effective_volume() <= 0.0:
		_skip_latest(normalized, "volume-zero")
		return
	var stream := _stream_for(normalized)
	if stream == null:
		_skip_latest(normalized, "stream-unavailable")
		return
	var channel := "ui" if normalized == "button" else "sfx"
	var player := _ui_player if channel == "ui" else _sfx_player
	if player == null:
		_skip_latest(normalized, "player-unavailable")
		return
	var active_priority := int(_active_priorities.get(channel, 0))
	if not player.playing:
		active_priority = 0
	if player.playing and priority < active_priority:
		_skip_latest(normalized, "priority-blocked")
		return
	player.stream = stream
	player.pitch_scale = _pitch_for(rhythm)
	player.volume_db = _volume_db(_effective_volume()) + (-8.0 if normalized == "button" else -4.0)
	player.play()
	_active_priorities[channel] = priority
	recent_feedback[0].played = true

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

func _setup_players() -> void:
	if _ui_player == null:
		_ui_player = AudioStreamPlayer.new()
		_ui_player.name = "UiPlayer"
		add_child(_ui_player)
	if _sfx_player == null:
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.name = "SfxPlayer"
		add_child(_sfx_player)

func _detect_audio() -> bool:
	if OS.has_feature("headless"):
		return false
	if DisplayServer.get_name().to_lower() == "headless":
		return false
	return AudioServer.get_bus_count() > 0

func _effective_muted() -> bool:
	return muted or (_is_mobile_runtime() and mobile_muted)

func _effective_volume() -> float:
	var mobile_multiplier := mobile_volume if _is_mobile_runtime() else 1.0
	return clampf(volume * mobile_multiplier, 0.0, 1.0)

func _is_mobile_runtime() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

func _emit_settings_changed() -> void:
	settings_changed.emit(audio_settings())

func _apply_player_settings() -> void:
	var db := _volume_db(_effective_volume())
	if _ui_player != null:
		_ui_player.volume_db = db - 8.0
	if _sfx_player != null:
		_sfx_player.volume_db = db - 4.0

func _stop_players() -> void:
	if _ui_player != null:
		_ui_player.stop()
	if _sfx_player != null:
		_sfx_player.stop()
	_active_priorities = {"ui": 0, "sfx": 0}

func _skip_latest(kind: String, reason: String) -> void:
	if not recent_feedback.is_empty():
		recent_feedback[0].played = false
	playback_skipped.emit(kind, reason)

func _next_rhythm(kind: String) -> Dictionary:
	if not rhythm_enabled:
		return {"group": kind, "step": 0, "accent": false}
	if kind == "attack":
		_rhythm_step = (_rhythm_step + 1) % RHYTHM_STEPS if _rhythm_kind == "attack" else 0
		_rhythm_kind = "attack"
		return {"group": "attack", "step": _rhythm_step, "accent": _rhythm_step == 0}
	_rhythm_kind = kind
	_rhythm_step = 0
	return {"group": kind, "step": 0, "accent": kind in ["alert", "victory", "defeat"]}

func _pitch_for(rhythm: Dictionary) -> float:
	var step := float(rhythm.get("step", 0))
	return 1.08 if bool(rhythm.get("accent", false)) else 0.98 + step * 0.025

func _volume_db(linear_volume: float) -> float:
	return 20.0 * log(maxf(linear_volume, 0.001)) / log(10.0)

func _normalize_kind(kind: String) -> String:
	var normalized := kind.strip_edges().to_lower()
	return normalized if normalized in DEFAULT_PRIORITIES else "button"

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
