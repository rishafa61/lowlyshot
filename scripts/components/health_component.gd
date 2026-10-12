class_name HealthComponent
extends Node

# ponytail: dead-state visuals/respawn timers stay in owners; upgrade to a shared DeathComponent when a third pattern appears.
signal damaged(amount: float, final_damage: float)
signal healed(amount: float)
signal armor_damaged(amount: float)
signal died

@export var max_health: float = 100.0
@export var max_armor: float = 0.0
@export var armor_absorption: float = 0.5

var health: float = 100.0
var armor: float = 0.0
var is_dead: bool = false

func _ready() -> void:
	reset()

func setup(new_max_health: float, new_max_armor: float = 0.0) -> void:
	max_health = new_max_health
	max_armor = new_max_armor
	reset()

func reset() -> void:
	health = max_health
	armor = max_armor
	is_dead = false

func apply_damage(amount: float, part_multiplier: float = 1.0) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var final_dmg = amount * part_multiplier
	var absorbed = minf(final_dmg * armor_absorption, armor)
	armor = maxf(0.0, armor - absorbed)
	health = maxf(0.0, health - (final_dmg - absorbed))
	damaged.emit(amount, final_dmg - absorbed)
	if absorbed > 0.0:
		armor_damaged.emit(absorbed)
	if health <= 0.0:
		is_dead = true
		died.emit()
	return final_dmg

func apply_percentage_damage(percent: float, is_insta_kill: bool = false) -> float:
	if is_dead:
		return 0.0
	var amount = max_health if is_insta_kill else max_health * percent
	return apply_damage(amount, 1.0)

func heal(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before = health
	health = minf(max_health, health + amount)
	var healed_amount = health - before
	if healed_amount > 0.0:
		healed.emit(healed_amount)
	return healed_amount

func repair_armor(amount: float) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var before = armor
	armor = minf(max_armor, armor + amount)
	return armor - before
