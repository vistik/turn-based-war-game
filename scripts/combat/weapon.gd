class_name Weapon
extends RefCounted

var name: String
var damage_min: int
var damage_max: int
var crit_chance: int
var crit_damage: int
var clip_size: int
## Aim modifier indexed by distance in tiles; the last entry applies to anything further.
var range_mods: PackedInt32Array


func _init(p_name: String, p_damage_min: int, p_damage_max: int, p_crit_chance: int, p_crit_damage: int, p_clip_size: int, p_range_mods: Array) -> void:
	name = p_name
	damage_min = p_damage_min
	damage_max = p_damage_max
	crit_chance = p_crit_chance
	crit_damage = p_crit_damage
	clip_size = p_clip_size
	range_mods = PackedInt32Array(p_range_mods)


func range_modifier(distance: float) -> int:
	return range_mods[clampi(roundi(distance), 0, range_mods.size() - 1)]


static func rifle() -> Weapon:
	return Weapon.new("Rifle", 3, 5, 10, 2, 4, [0, 15, 12, 9, 6, 3, 0, 0, 0, 0, 0, 0, -5, -10, -15, -20, -25])


static func shotgun() -> Weapon:
	return Weapon.new("Shotgun", 4, 6, 20, 3, 4, [0, 45, 35, 25, 15, 5, -5, -15, -25, -35, -45, -55])
