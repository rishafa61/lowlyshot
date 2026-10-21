extends Node
class_name StaticBatcher

## Draw-call optimizer for the GL Compatibility renderer.
##
## Compatibility has NO automatic instancing/batching: every MeshInstance3D is one draw call,
## and the sun's shadow cascades draw every caster again. Ground War has ~850 static prop
## meshes that share just a handful of meshes/materials, so this node merges them at level
## load into chunked MultiMeshInstance3Ds (one draw call per mesh+material+chunk).
##
## Only plain, static props are merged. Collision shapes are never touched, and the
## scene file on disk is unchanged (navmesh baking / editing keep working).
## A mesh is skipped if it has children, a script, a surface override material, a
## visibility range, or any ancestor that is scripted / physics-driven / not a plain Node3D.

@export var enabled: bool = true
## Props are grouped per square chunk so frustum culling still works across the 800 m map.
@export var chunk_size: float = 160.0
## Don't bother merging a mesh+material combo that has fewer instances than this in a chunk.
@export var min_group_size: int = 2

const ALLOWED_ANCESTORS := ["Node3D", "StaticBody3D", "NavigationRegion3D"]

## Tests only: remember the exact (mesh, material, transform) triples handed to the MultiMeshes.
var debug_record: bool = false
var debug_instances: Array = []
var stats: Dictionary = {}

func _ready() -> void:
	if enabled:
		call_deferred("run")

func run() -> Dictionary:
	var root: Node = get_parent()
	var groups: Dictionary = {}
	var scanned := 0
	_collect(root, root, groups)
	var merged := 0
	var batches := 0
	for key in groups.keys():
		var g: Dictionary = groups[key]
		var nodes: Array = g["nodes"]
		scanned += nodes.size()
		if nodes.size() < min_group_size:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g["mesh"]
		mm.instance_count = nodes.size()
		for i in nodes.size():
			var xf: Transform3D = (nodes[i] as MeshInstance3D).global_transform
			mm.set_instance_transform(i, xf)
			if debug_record:
				debug_instances.append([g["mesh"].get_instance_id(), g["mat"].get_instance_id() if g["mat"] else 0, xf])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch_%d" % batches
		mmi.multimesh = mm
		mmi.material_override = g["mat"]
		mmi.cast_shadow = g["shadow"]
		mmi.layers = g["layers"]
		mmi.gi_mode = g["gi"]
		add_child(mmi) # parent is a plain Node => world-space instance transforms
		for n in nodes:
			(n as Node).queue_free()
		merged += nodes.size()
		batches += 1
	stats = {"candidates": scanned, "merged": merged, "batches": batches}
	print("[StaticBatcher] merged %d static meshes into %d MultiMesh batches" % [merged, batches])
	return stats

func _collect(n: Node, root: Node, groups: Dictionary) -> void:
	for c in n.get_children():
		if c == self:
			continue
		if c is MeshInstance3D and _is_mergeable(c as MeshInstance3D, root):
			var mi := c as MeshInstance3D
			var p := mi.global_position
			var key := "%d|%d|%d|%d|%d|%d|%d" % [
				mi.mesh.get_instance_id(),
				mi.material_override.get_instance_id() if mi.material_override else 0,
				int(mi.cast_shadow), mi.layers, int(mi.gi_mode),
				floori(p.x / chunk_size), floori(p.z / chunk_size)]
			if not groups.has(key):
				groups[key] = {
					"mesh": mi.mesh, "mat": mi.material_override,
					"shadow": mi.cast_shadow, "layers": mi.layers, "gi": mi.gi_mode,
					"nodes": [],
				}
			groups[key]["nodes"].append(mi)
		_collect(c, root, groups)

func _is_mergeable(mi: MeshInstance3D, root: Node) -> bool:
	if mi.mesh == null or not mi.visible or mi.get_child_count() > 0 or mi.get_script() != null:
		return false
	if mi.visibility_range_end > 0.0 or mi.visibility_range_begin > 0.0 or mi.skin != null:
		return false
	for s in mi.mesh.get_surface_count():
		if mi.get_surface_override_material(s) != null:
			return false
	var a: Node = mi.get_parent()
	while a != null and a != root:
		if not (a is Node3D) or not (a.get_class() in ALLOWED_ANCESTORS) or a.get_script() != null:
			return false
		if not (a as Node3D).visible:
			return false
		a = a.get_parent()
	return true
