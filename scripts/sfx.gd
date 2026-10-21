extends Node
## Central 3D sound helper. One-shots spawn a self-freeing AudioStreamPlayer3D;
## loops return the player so callers can stop it. 3D distance attenuation makes
## far-away sources quieter automatically (unit_size + max_distance tuned per call).

const SOUNDS := {
	"rifle_single": "res://assets/sounds/Rifle - Single Shot.tres",
	"rifle_reload": "res://assets/sounds/Rifle - Reload.tres",
	"sniper_shot": "res://assets/sounds/Sniper Shot.tres",
	"sniper_bolt": "res://assets/sounds/Sniper Bolt Action.tres",
	"walk": "res://assets/sounds/Player - Walk.tres",
	"run": "res://assets/sounds/Player - Run.tres",
	"slide": "res://assets/sounds/Player - Slide.tres",
	"jet": "res://assets/sounds/Aircraft Jet Engine.tres",
	"missile": "res://assets/sounds/Aircraft - Launch Missile.tres",
	"bomb": "res://assets/sounds/Aircraft Dropping Bomb.tres",
	"heli": "res://assets/sounds/Helicopter Sound.tres",
	"humvee": "res://assets/sounds/Humvee.tres",
	# Synthesized at runtime in _synthesize_cues() (no files needed)
	"bomb_tick": "",
	"round_win": "",
	"round_loss": "",
}

var _streams := {}
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"

func _ready() -> void:
	_ensure_bus(SFX_BUS)
	_ensure_bus(MUSIC_BUS)
	for key in SOUNDS:
		var s: AudioStream = load(SOUNDS[key])
		if s:
			# Duplicate: imported resources are read-only; we own an editable
			# copy so loop points etc. can be set at runtime.
			_streams[key] = s.duplicate()
		else:
			push_warning("Sfx: missing sound file %s" % SOUNDS[key])
	# ponytail: synthesized cues instead of recorded WAVs — swap in real
	# recordings by adding files to SOUNDS; the generated ones yield.
	_synthesize_cues()
	apply_volumes()

## Builds the small UI/gameplay cues (bomb beep, round stingers) procedurally.
## No binary assets to track; regenerating is free.
func _synthesize_cues() -> void:
	if not _streams.has("bomb_tick"):
		_streams["bomb_tick"] = _make_tone(1600.0, 0.09, 0.5, -6.0)
	if not _streams.has("round_win"):
		_streams["round_win"] = _make_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.14)
	if not _streams.has("round_loss"):
		_streams["round_loss"] = _make_arpeggio([440.0, 349.23, 261.63], 0.22)

const _TONE_RATE := 22050

func _make_tone(freq: float, dur: float, amp: float, _vol := 0.0) -> AudioStreamWAV:
	var n := int(dur * _TONE_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		# Exponential decay envelope kills the click at the end
		var env := exp(-6.0 * float(i) / float(n))
		var v := int(clampf(sin(TAU * freq * float(i) / _TONE_RATE) * amp * env, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _TONE_RATE
	wav.stereo = false
	wav.data = data
	return wav

func _make_arpeggio(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var n := int(note_dur * _TONE_RATE)
	var data := PackedByteArray()
	data.resize(n * freqs.size() * 2)
	for note in freqs.size():
		for i in n:
			var idx := note * n + i
			var env: float = 1.0 - float(i) / float(n)
			var v := int(clampf(sin(TAU * float(freqs[note]) * float(i) / _TONE_RATE) * 0.45 * env, -1.0, 1.0) * 32767.0)
			data.encode_s16(idx * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = _TONE_RATE
	wav.stereo = false
	wav.data = data
	return wav

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.bus_count > 0 and AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

## Reads GlobalSettings volumes into the SFX/Music buses. Call after any
## slider change — bus gain multiplies on top of each player's volume_db,
## so persistent loops (rotor/engine) update live too.
func apply_volumes() -> void:
	var gs = get_node_or_null("/root/GlobalSettings")
	var sfx_vol := 100.0
	var bgm_vol := 80.0
	if gs != null:
		sfx_vol = float(gs.get("sfx_vol"))
		bgm_vol = float(gs.get("bgm_vol"))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(maxf(sfx_vol / 100.0, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(maxf(bgm_vol / 100.0, 0.0001)))

func has(key: String) -> bool:
	return _streams.has(key)

## Fire-and-forget 2D sound for global UI / round stingers (self-frees when done).
func oneshot2d(key: String, vol_db := 0.0) -> void:
	if not _streams.has(key):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[key]
	p.volume_db = vol_db
	p.bus = SFX_BUS
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()

## Fire-and-forget positional sound attached to a node (self-frees when done).
func oneshot3d(key: String, at: Node3D, unit_size := 10.0, max_dist := 80.0, vol_db := 0.0) -> void:
	if not _streams.has(key) or at == null or not is_instance_valid(at):
		return
	var p := _make_player(key, at, unit_size, max_dist, vol_db)
	p.finished.connect(p.queue_free)
	p.play()

## Persistent positional loop. Caller keeps the reference and calls stop_loop().
func loop3d(key: String, at: Node3D, unit_size := 10.0, max_dist := 80.0, vol_db := 0.0) -> AudioStreamPlayer3D:
	if not _streams.has(key) or at == null or not is_instance_valid(at):
		return null
	var p := _make_player(key, at, unit_size, max_dist, vol_db)
	# Loop the wav regardless of import flags. Duplicate the stream so the
	# loop edit doesn't leak into every user of the shared imported resource.
	var wav := p.stream as AudioStreamWAV
	if wav and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav = wav.duplicate()
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		@warning_ignore("integer_division")
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
		p.stream = wav
	p.play()
	return p

## High-rate pooled 3D sound (for miniguns/gatlings at 8-15 Hz). Reuses 4
## pre-allocated players attached to the source so there's zero heap churn.
func pool_fire3d(key: String, at: Node3D, unit_size := 14.0, max_dist := 140.0, vol_db := 0.0) -> void:
	if not _streams.has(key) or at == null or not is_instance_valid(at):
		return
	var pool: Array = at.get_meta("_sfx_pool_" + key, [])
	if pool.is_empty():
		for i in 4:
			var player_node := _make_player(key, at, unit_size, max_dist, vol_db)
			pool.append(player_node)
		at.set_meta("_sfx_pool_" + key, pool)
	var idx: int = at.get_meta("_sfx_idx_" + key, 0)
	var p: AudioStreamPlayer3D = pool[idx]
	if is_instance_valid(p):
		p.pitch_scale = randf_range(0.96, 1.04) # slight variation avoids machine-gun phasing
		p.play()
	at.set_meta("_sfx_idx_" + key, (idx + 1) % pool.size())

func stop_loop(p: AudioStreamPlayer3D) -> void:
	if p and is_instance_valid(p):
		p.queue_free()

func _make_player(key: String, at: Node3D, unit_size: float, max_dist: float, vol_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[key]
	p.unit_size = unit_size
	p.max_distance = max_dist
	p.volume_db = vol_db
	p.bus = SFX_BUS # settings slider controls this bus — applies to every game sound
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	at.add_child(p)
	return p
