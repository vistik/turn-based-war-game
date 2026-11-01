class_name Theatres
extends RefCounted
## Every theatre the game knows, by id. Battles, saves, scenarios and online setups name their theatre by id;
## anything without one is Normandy, the original.

const DEFAULT := "normandy"
## In the order the menu offers them.
const IDS := ["normandy", "vietnam", "modern"]

static var _theatres := {}
static var _lock := Mutex.new()


static func get_theatre(theatre_id: String) -> Theatre:
	_lock.lock()
	if _theatres.is_empty():
		_theatres["normandy"] = NormandyTheatre.new()
		_theatres["vietnam"] = VietnamTheatre.new()
		_theatres["modern"] = ModernTheatre.new()
	var result: Theatre = _theatres.get(theatre_id, _theatres[DEFAULT])
	_lock.unlock()
	return result


static func exists(theatre_id: String) -> bool:
	return IDS.has(theatre_id)


static func all() -> Array[Theatre]:
	var result: Array[Theatre] = []
	for theatre_id: String in IDS:
		result.append(get_theatre(theatre_id))
	return result
