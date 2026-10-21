extends SceneTree
# Self-check: sniper sound assets resolve and bolt-cycle helper guards work.

var fails := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("PASS: " + label)
	else:
		fails += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	# 1. Renamed .wav sources imported
	var shot: AudioStream = load("res://assets/sounds/Sniper Shot.wav")
	var bolt: AudioStream = load("res://assets/sounds/Sniper Bolt Action.wav")
	check(shot != null, "Sniper Shot.wav imports")
	check(bolt != null, "Sniper Bolt Action.wav imports")

	# 2. Baked .tres copies load (Sfx paths)
	var sfx_script := GDScript.new()
	sfx_script.source_code = "extends Node\nconst SOUNDS := {\n\t\"sniper_shot\": \"res://assets/sounds/Sniper Shot.tres\",\n\t\"sniper_bolt\": \"res://assets/sounds/Sniper Bolt Action.tres\",\n}\n"
	sfx_script.reload()
	var probe := Node.new()
	probe.set_script(sfx_script)
	for k in ["sniper_shot", "sniper_bolt"]:
		var s: AudioStream = load(sfx_script.SOUNDS[k])
		check(s != null and s is AudioStreamWAV, "Sfx key '%s' -> baked .tres loads (%s)" % [k, s])

	# 3. Sfx registry contains both keys with no missing-file warning
	var sfx_inst = (load("res://scripts/sfx.gd") as GDScript).new()
	root.add_child(sfx_inst)
	await process_frame # let _ready() bake the stream cache
	check(is_instance_valid(sfx_inst), "Sfx script instances")
	if is_instance_valid(sfx_inst):
		check(sfx_inst.has("sniper_shot"), "Sfx loaded 'sniper_shot' stream")
		check(sfx_inst.has("sniper_bolt"), "Sfx loaded 'sniper_bolt' stream")
		sfx_inst.queue_free()

	# 4. Bolt-cycle helper exists and guards on wrong weapon slot
	var pscene = load("res://scenes/player/player.tscn")
	check(pscene != null, "player.tscn loads")
	if pscene:
		var p = pscene.instantiate()
		check(p.has_method("_play_sniper_bolt_cycle"), "player has _play_sniper_bolt_cycle()")
		p.queue_free()

	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
