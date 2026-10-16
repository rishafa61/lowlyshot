extends Node
## Central 3D sound helper. One-shots spawn a self-freeing AudioStreamPlayer3D;
## loops return the player so callers can stop it. 3D distance attenuation makes
## far-away sources quieter automatically (unit_size + max_distance tuned per call).

const SOUNDS := {
	"rifle_single": "res://assets/sounds/Rifle - Single Shot.wav",
	"rifle_hold": "res://assets/sounds/Rifle - Hold Trigger.wav",
	"rifle_reload": "res://assets/sounds/Rifle - Reload.wav",
	"sniper_shot": "res://assets/sounds/Sniper - Shot.wav",
	"walk": "res://assets/sounds/Player - Walk.wav",
	"run": "res://assets/sounds/Player - Run.wav",
	"slide": "res://assets/sounds/Player - Slide.wav",
	"jet": "res://assets/sounds/Aircraft Jet Engine.wav",
	"missile": "res://assets/sounds/Aircraft - Launch Missile.wav",
	"bomb": "res://assets/sounds/Aircraft Dropping Bomb.wav",
	"heli": "res://assets/sounds/Helicopter Sound.wav",
	"humvee": "res://assets/sounds/Humvee.wav",
}

var _streams := {}

func _ready() -> void:
	for key in SOUNDS:
		var s: AudioStream = load(SOUNDS[key])
		if s:
			_streams[key] = s
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
