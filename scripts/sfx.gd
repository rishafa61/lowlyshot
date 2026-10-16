extends Node
## Central 3D sound helper. One-shots spawn a self-freeing AudioStreamPlayer3D;
## loops return the player so callers can stop it. 3D distance attenuation makes
## far-away sources quieter automatically (unit_size + max_distance tuned per call).

const SOUNDS := {
	"rifle_single": "res://assets/sounds/Rifle - Single Shot.tres",
	"rifle_reload": "res://assets/sounds/Rifle - Reload.tres",
	"sniper_shot": "res://assets/sounds/Sniper - Shot.tres",
	"walk": "res://assets/sounds/Player - Walk.tres",
	"run": "res://assets/sounds/Player - Run.tres",
	"slide": "res://assets/sounds/Player - Slide.tres",
	"jet": "res://assets/sounds/Aircraft Jet Engine.tres",
	"missile": "res://assets/sounds/Aircraft - Launch Missile.tres",
	"bomb": "res://assets/sounds/Aircraft Dropping Bomb.tres",
	"heli": "res://assets/sounds/Helicopter Sound.tres",
	"humvee": "res://assets/sounds/Humvee.tres",
}

var _streams := {}

func _ready() -> void:
	for key in SOUNDS:
		var s: AudioStream = load(SOUNDS[key])
		if s:
			# Duplicate: imported resources are read-only; we own an editable
			# copy so loop points etc. can be set at runtime.
			_streams[key] = s.duplicate()
		else:
			push_warning("Sfx: missing sound file %s" % SOUNDS[key])

func has(key: String) -> bool:
	return _streams.has(key)

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
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	at.add_child(p)
	return p
