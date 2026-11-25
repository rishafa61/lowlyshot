class_name WeaponData
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var type: String = "gun"
@export var dmg: float = 30.0
@export var rng: float = 50.0
@export var stab: float = 50.0
@export var fire_rate: float = 0.1
@export var mag: int = 30
@export var max_mag: int = 30
@export var res: int = 90
@export var max_res: int = 90
@export var auto: bool = true
@export var is_shotgun: bool = false
@export var pellets: int = 1
@export var spread_base: float = 0.0
@export var reload_time: float = 0.0 # 0 = engine default (RELOAD_TIME in player.gd)
@export var recoil_v: float = 0.05 # camera pitch punch per shot
@export var recoil_h: float = 0.0 # camera yaw wander per shot
@export var kick_vm: float = 0.15 # viewmodel push-back per shot
@export var spread_per_shot: float = 0.02 # sustained-fire accuracy loss
@export var speed_mult: float = 1.0 # movement multiplier while equipped (LMG < 1.0)
@export var is_sniper: bool = false
@export var owned: bool = false
@export var equipped: bool = false
@export var price: int = 0
@export var scene_path: String = ""
@export var viewmodel_scene: String = "" # first-person model scene (anim-capable); "" = reuse scene_path

@export var viewmodel_position: Vector3 = Vector3.ZERO
@export var viewmodel_rotation: Vector3 = Vector3.ZERO
@export var viewmodel_scale: Vector3 = Vector3.ONE

@export var hold_style: String = "rifle" # "rifle", "pistol", "melee", "util"
@export var right_hand_offset: Vector3 = Vector3.ZERO
@export var left_hand_offset: Vector3 = Vector3.ZERO

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"type": type,
		"dmg": dmg,
		"rng": rng,
		"stab": stab,
		"fire_rate": fire_rate,
		"mag": mag,
		"max_mag": max_mag,
		"res": res,
		"max_res": max_res,
		"auto": auto,
		"is_shotgun": is_shotgun,
		"pellets": pellets,
		"spread_base": spread_base,
		"reload_time": reload_time,
		"recoil_v": recoil_v,
		"recoil_h": recoil_h,
		"kick_vm": kick_vm,
		"spread_per_shot": spread_per_shot,
		"speed_mult": speed_mult,
		"is_sniper": is_sniper,
		"owned": owned,
		"equipped": equipped,
		"price": price,
		"scene_path": scene_path,
		"viewmodel_scene": viewmodel_scene,
		"viewmodel_position": viewmodel_position,
		"viewmodel_rotation": viewmodel_rotation,
		"viewmodel_scale": viewmodel_scale,
		"hold_style": hold_style,
		"right_hand_offset": right_hand_offset,
		"left_hand_offset": left_hand_offset
	}

static func from_dict(d: Dictionary) -> WeaponData:
	var w = WeaponData.new()
	w.id = d.get("id", "")
	w.display_name = d.get("name", "")
	w.type = d.get("type", "gun")
	w.dmg = float(d.get("dmg", 30.0))
	w.rng = float(d.get("rng", 50.0))
	w.stab = float(d.get("stab", 50.0))
	w.fire_rate = float(d.get("fire_rate", 0.1))
	w.mag = int(d.get("mag", 30))
	w.max_mag = int(d.get("max_mag", w.mag))
	w.res = int(d.get("res", 90))
	w.max_res = int(d.get("max_res", w.res))
	w.auto = bool(d.get("auto", true))
	w.is_shotgun = bool(d.get("is_shotgun", false))
	w.pellets = int(d.get("pellets", 1))
	w.spread_base = float(d.get("spread_base", 0.0))
	w.reload_time = float(d.get("reload_time", 0.0))
	w.recoil_v = float(d.get("recoil_v", 0.05))
	w.recoil_h = float(d.get("recoil_h", 0.0))
	w.kick_vm = float(d.get("kick_vm", 0.15))
	w.spread_per_shot = float(d.get("spread_per_shot", 0.02))
	w.speed_mult = float(d.get("speed_mult", 1.0))
	w.is_sniper = bool(d.get("is_sniper", false))
	w.owned = bool(d.get("owned", false))
	w.equipped = bool(d.get("equipped", false))
	w.price = int(d.get("price", 0))
	w.scene_path = d.get("scene_path", "")
	w.viewmodel_scene = d.get("viewmodel_scene", "")
	w.viewmodel_position = d.get("viewmodel_position", Vector3.ZERO)
	w.viewmodel_rotation = d.get("viewmodel_rotation", Vector3.ZERO)
	w.viewmodel_scale = d.get("viewmodel_scale", Vector3.ONE)
	w.hold_style = d.get("hold_style", "rifle")
	w.right_hand_offset = d.get("right_hand_offset", Vector3.ZERO)
	w.left_hand_offset = d.get("left_hand_offset", Vector3.ZERO)
	return w
