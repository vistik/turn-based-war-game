class_name Weapon
extends RefCounted

var name: String
## rifle, smg, mg, sniper, carbine, pistol, at or tank. Drives the soldier art and how it is held.
var kind: String
var damage_min: int
var damage_max: int
var crit_chance: int
var crit_damage: int
var clip_size: int
## Suppression every shot adds to its target, hit or miss.
var suppression: int
## Aim modifier indexed by distance in tiles; the last entry applies to anything further.
var range_mods: PackedInt32Array
## Machine guns must be set up before firing, and suppress everyone around the target.
var needs_setup := false
## Can damage tanks. Everything else bounces off their armour.
var anti_tank := false
## Tank guns fire high explosive: a hit or near miss also blasts everything within this radius.
var blast_radius := 0.0


func _init(p_name: String, p_kind: String, p_damage: Vector2i, p_crit_chance: int, p_crit_damage: int, p_clip_size: int, p_suppression: int, p_range_mods: Array, p_needs_setup := false) -> void:
	name = p_name
	kind = p_kind
	damage_min = p_damage.x
	damage_max = p_damage.y
	crit_chance = p_crit_chance
	crit_damage = p_crit_damage
	clip_size = p_clip_size
	suppression = p_suppression
	range_mods = PackedInt32Array(p_range_mods)
	needs_setup = p_needs_setup


## Range tables are written per tile at the old scale; every distance is divided by this, so weapons hold
## their accuracy 1.5 times as far (as do sight ranges, set in the theatres' role data).
const RANGE_SCALE := 1.5


func range_modifier(distance: float) -> int:
	return range_mods[clampi(roundi(distance / RANGE_SCALE), 0, range_mods.size() - 1)]


## A weapon from its data (see the theatres): {"name", "kind", "damage": [min, max], "crit", "crit_damage", "clip",
## "suppression", "range": [modifier per tile...], and optionally "setup", "anti_tank", "blast"}.
static func from_spec(spec: Dictionary) -> Weapon:
	var weapon := Weapon.new(spec["name"], spec["kind"], Vector2i(spec["damage"][0], spec["damage"][1]), spec["crit"], spec["crit_damage"],
			spec["clip"], spec["suppression"], spec["range"], spec.get("setup", false))
	weapon.anti_tank = spec.get("anti_tank", false)
	weapon.blast_radius = spec.get("blast", 0.0)
	return weapon
