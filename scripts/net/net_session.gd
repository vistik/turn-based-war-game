extends Node
## Online play between two copies of the game with no server in between: one player hosts (listens on a
## port), the other joins by address. The host sends the battle setup once; from then on the games only
## exchange commands. Both run the same deterministic engine, and every command carries the sender's state
## checksum after applying it, so the receiver notices at once if the two games ever disagree.
##
## Autoloaded as `Net`. The host plays the Allies, the joining player Germany.

signal peer_joined
signal setup_received(setup: Dictionary)
signal command_received
signal desynced(reason: String)
signal disconnected
signal connection_failed

const DEFAULT_PORT := 24944
## Bumped whenever the rules or the protocol change, so different versions refuse to play each other.
const PROTOCOL := 1

## True while connected to an opponent.
var active := false
var is_host := false
var local_team := 0
## Commands from the opponent waiting to be applied: {"command", "checksum"}.
var _queue: Array[Dictionary] = []
## Bumped by close(), so anyone still waiting on a closed session gives up.
var _session := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_peer_disconnected.bind(1))


func host(port := DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_team = 0
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	local_team = 1
	return OK


func close() -> void:
	_session += 1
	active = false
	_queue.clear()
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	# Wake anyone waiting for a command so they see the session is over.
	command_received.emit()


func remote_team() -> int:
	return 1 - local_team


## IPv4 addresses of this machine the other player could connect to.
static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result


## Host only: tell the joined player which battle to build.
func send_setup(setup: Dictionary) -> void:
	_receive_setup.rpc(setup)


func send_command(command: Dictionary, checksum: String) -> void:
	if active:
		_receive_command.rpc(command, checksum)


## Waits for the opponent's next command. Returns {} if the session closes first.
func next_command() -> Dictionary:
	var session := _session
	while _queue.is_empty():
		await command_received
		if session != _session:
			return {}
	return _queue.pop_front()


## Tells both sides the games no longer match.
func report_desync(reason: String) -> void:
	if active:
		_peer_desynced.rpc(reason)
	desynced.emit(reason)


# --- Remote calls ---

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_refuse.rpc_id(sender, "The other game is a different version.")
		return
	active = true
	peer_joined.emit()


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	push_warning(reason)
	_on_connection_failed.call_deferred()


@rpc("authority", "call_remote", "reliable")
func _receive_setup(setup: Dictionary) -> void:
	active = true
	setup_received.emit(setup)


@rpc("any_peer", "call_remote", "reliable")
func _receive_command(command: Dictionary, checksum: String) -> void:
	_queue.append({"command": command, "checksum": checksum})
	command_received.emit()


@rpc("any_peer", "call_remote", "reliable")
func _peer_desynced(reason: String) -> void:
	desynced.emit("The other game reports: " + reason)


# --- Connection events ---
# These arrive while the multiplayer peer is being polled, so the peer is only closed afterwards.

func _on_peer_connected(_id: int) -> void:
	pass


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, PROTOCOL)


func _on_peer_disconnected(_id: int) -> void:
	_lost_peer.call_deferred(active)


func _lost_peer(was_active: bool) -> void:
	close()
	if was_active:
		disconnected.emit()


func _on_connection_failed() -> void:
	close.call_deferred()
	connection_failed.emit.call_deferred()
