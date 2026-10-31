class_name RemotePlayer
extends RefCounted
## Controller for the side played by the online opponent: applies their commands as they arrive and checks
## that our game ends up in exactly the state theirs did.

var battle: Battle
var team: int
## The Net session the commands arrive through.
var net: Node


func _init(p_battle: Battle, p_team: int, p_net: Node) -> void:
	battle = p_battle
	team = p_team
	net = p_net


## Waits for the opponent's next command and applies it. Returns its events, or null if the session ended
## or the games no longer match (net has then signalled why). When the command changed the turn or ended the
## battle, tells both sides the games agree there, which is where online games are saved.
func next_events() -> Variant:
	var received: Dictionary = await net.next_command()
	if received.is_empty():
		return null
	var command: Dictionary = received["command"]
	var unit := battle.get_unit(command.get("unit", -1))
	if command.get("cmd") != "end_turn" and (unit == null or unit.team != team):
		net.report_desync("The opponent sent an order for a unit that isn't theirs.")
		return null
	var turn_before := battle.turn_index
	var events := battle.execute(command)
	if events.is_empty():
		net.report_desync("The opponent's order %s isn't possible in this game." % command.get("cmd"))
		return null
	if battle.checksum() != received["checksum"]:
		net.report_desync("The battle differs after the opponent's %s." % command.get("cmd"))
		return null
	if battle.turn_index != turn_before or battle.winner != -1:
		net.agree_turn(battle.turn_index, received["checksum"])
	return events


## Nothing to save: the opponent's game holds their side's state.
func to_dict() -> Dictionary:
	return {}
