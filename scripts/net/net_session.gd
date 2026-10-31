extends Node
## Online play between two copies of the game with no server in between: one player hosts (listens on a
## port), the other joins by address. The host sends the battle setup once; from then on the games only
## exchange commands. Both run the same deterministic engine, and every command carries the sender's state
## checksum after applying it, so the receiver notices at once if the two games ever disagree.
##
## A saved online game is continued the same way: the host offers its saved battle instead of a setup, the
## joining player loads it (after confirming, if their own save differs), and play only resumes once the host
## has seen that both loaded games have the same checksum.
##
## Every game is protected by a password the two players agree on (it may be empty on a home network). The
## joining player proves it knows the password before the host lets it in, and the host proves it back, both
## with HMACs over fresh random nonces, so the password itself never travels. Until then the host ignores
## everything else the newcomer sends, turns away anyone else, and locks out a run of wrong guesses.
##
## Over the internet, before hosting or joining, prepare_internet() asks the router to forward the port (UPnP)
## and a public STUN server which address the internet sees. If the router won't forward, the joiner sends
## its own internet address to the host, who lets it in with let_in(): the host sends packets towards it from
## the game port, which opens the host's NAT for the joiner's connection attempts (hole punching).
##
## Autoloaded as `Net`. In a new game the host plays the Allies, the joining player Germany; in a continued
## game each keeps the side they had.

signal peer_joined
signal setup_received(setup: Dictionary)
signal command_received
signal desynced(reason: String)
signal disconnected
signal connection_failed
## Joiner: the host offers a saved game to continue (see GameSession.online_offer).
signal resume_offered(offer: Dictionary)
## Both: the two games loaded the same saved battle; play on.
signal resume_started
## Host: the joining player chose not to continue the saved game.
signal resume_declined
## Both games agree on the state after a turn change: the turn index and checksum to save at.
signal turn_agreed(turn_index: int, checksum: String)

const DEFAULT_PORT := 24944
## Bumped whenever the rules or the protocol change, so different versions refuse to play each other.
const PROTOCOL := 7
## How many players may be connecting at once while the host waits; only one gets in.
const MAX_KNOCKING := 4
## Seconds a newcomer has to prove it knows the password.
const AUTH_TIMEOUT := 10.0
## This many wrong passwords within LOCKOUT seconds turn everyone away for LOCKOUT seconds.
const MAX_FAILURES := 5
const LOCKOUT := 60.0
## SHA-256 rounds that stretch the password into the key, to slow down guessing.
const KEY_ROUNDS := 20000
## Joiner: how long to keep trying to reach a host over the internet, while the host lets it in.
const JOIN_PATIENCE := 90.0
## Host: how long to keep sending packets towards a joiner it was asked to let in.
const PUNCH_TIME := 60.0

## True while connected to an opponent.
var active := false
var is_host := false
var local_team := 0
## Where the opponent is: the address joined, or the address they joined from. A hint for the saved game.
var opponent := ""
## Commands from the opponent waiting to be applied: {"command", "checksum"}.
var _queue: Array[Dictionary] = []
## Bumped by close(), so anyone still waiting on a closed session gives up.
var _session := 0
## Host, while offering a saved game: the checksum the joining player must load.
var _resume_checksum := ""
## Shared with the other player; set before host() or join(). "" works too, if both leave it empty.
var password := ""
## Why the last attempt to connect failed, for the player ("" if we don't know).
var last_error := ""
## The password stretched into the HMAC key.
var _key := PackedByteArray()
## Host: the peer id of the player who got in (0 while waiting).
var _peer_id := 0
## Host: newcomers that haven't proved the password yet, peer id -> the nonce they were sent.
var _pending := {}
## Host: when recent wrong passwords came in (seconds), and until when everyone is turned away.
var _failures: Array[float] = []
var _locked_until := 0.0
## Joiner: the host has proved it knows the password, so its setup can be trusted.
var _welcomed := false
## Joiner: [host nonce, our nonce] of the handshake in progress.
var _join_nonces := []
## Joiner: [address, port, local port] being joined, retried until _join_deadline while the host punches.
var _join_target := []
var _join_deadline := 0
## What prepare_internet() found: our internet address via UPnP or STUN, and the STUN server used.
var internet_address := ""
var router_opened := false
var _stun_server := []
## The router mapping to remove when the game closes: [UPNP, port].
var _router_mapping := []
## Host: [address, port] of a joiner being let in, and until when (msec).
var _punch_target := []
var _punch_until := 0
var _next_keepalive := 0
var _ticker: Timer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_peer_disconnected.bind(1))
	# Only the host and the one player it let in talk; nothing is passed on between other peers.
	(multiplayer as SceneMultiplayer).server_relay = false
	_ticker = Timer.new()
	_ticker.wait_time = 0.25
	_ticker.timeout.connect(_tick)
	add_child(_ticker)


func _exit_tree() -> void:
	close()


## `team` is the side the host plays: the Allies in a new game, or its side in a continued one.
func host(port := DEFAULT_PORT, team := 0) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_KNOCKING)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_team = team
	_key = password_key(password)
	_ticker.start()
	return OK


## `local_port` is the port to send from: the one prepare_internet() looked up, so the host can punch
## through to it. Over the internet the attempt is repeated for a while, in case the host is still letting
## us in.
func join(address: String, port := DEFAULT_PORT, local_port := 0) -> Error:
	_reset()
	is_host = false
	local_team = 1
	opponent = "%s:%d" % [address, port]
	_key = password_key(password)
	_join_target = [address, port, local_port]
	_join_deadline = 0 if Nat.is_local(address) else Time.get_ticks_msec() + int(JOIN_PATIENCE * 1000)
	return _connect_to_host()


func _connect_to_host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(_join_target[0], _join_target[1], 0, 0, 0, _join_target[2])
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Leaves the game, and gives the router its port back.
func close() -> void:
	_reset()
	internet_address = ""
	router_opened = false
	_stun_server = []
	if not _router_mapping.is_empty():
		(_router_mapping[0] as UPNP).delete_port_mapping(_router_mapping[1], "UDP")
		_router_mapping = []


## Drops the connection, keeping what prepare_internet() found.
func _reset() -> void:
	_session += 1
	active = false
	_resume_checksum = ""
	_queue.clear()
	_peer_id = 0
	_pending.clear()
	_welcomed = false
	_join_nonces = []
	_join_target = []
	_punch_target = []
	if _ticker != null:
		_ticker.stop()
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	# Wake anyone waiting for a command so they see the session is over.
	command_received.emit()


## Before hosting or joining over the internet: finds the address the internet sees us at when sending from
## `port`, and (hosting) asks the router to forward the port. Takes a few seconds. Sets internet_address
## (the router's forwarded address if it agreed, else what STUN saw, else "") and router_opened.
func prepare_internet(port: int, open_router: bool) -> void:
	close()
	var session := _session
	var thread: Thread = null
	if open_router:
		thread = Thread.new()
		thread.start(Nat.open_router_port.bind(port))
	var seen := await _stun_lookup(port)
	var mapping := {}
	if thread != null:
		while thread.is_alive():
			await get_tree().process_frame
		mapping = thread.wait_to_finish()
	if session != _session:
		if not mapping.is_empty():
			mapping["upnp"].delete_port_mapping(port, "UDP")
		return
	internet_address = seen
	if not mapping.is_empty():
		_router_mapping = [mapping["upnp"], port]
		router_opened = true
		internet_address = mapping["address"]


## Host: the joiner at `address` ("ip:port", their internet address) can't get through the NAT; keep sending
## it packets from the game port for a while, which opens the way. False if the address doesn't parse.
func let_in(address: String) -> bool:
	var parts := Nat.split_address(address, 0)
	if not is_host or parts[1] <= 0 or not parts[0].is_valid_ip_address():
		return false
	_punch_target = parts
	_punch_until = Time.get_ticks_msec() + int(PUNCH_TIME * 1000)
	return true


## Asks the STUN servers in turn what address they see us at, sending from `port`. "" if none answer.
func _stun_lookup(port: int) -> String:
	var session := _session
	var udp := PacketPeerUDP.new()
	if udp.bind(port) != OK:
		return ""
	var result := ""
	for server: Array in Nat.STUN_SERVERS:
		var ip := await _resolve(server[0])
		if session != _session:
			break
		if ip == "":
			continue
		var transaction := Crypto.new().generate_random_bytes(12)
		udp.set_dest_address(ip, server[1])
		var deadline := Time.get_ticks_msec() + 1200
		var next_send := 0
		while result == "" and Time.get_ticks_msec() < deadline and session == _session:
			if Time.get_ticks_msec() >= next_send:
				udp.put_packet(Nat.stun_request(transaction))
				next_send = Time.get_ticks_msec() + 400
			while udp.get_available_packet_count() > 0:
				var answer := Nat.stun_address(udp.get_packet(), transaction)
				if answer != "":
					result = answer
			if result == "":
				await get_tree().process_frame
		if result != "":
			_stun_server = [ip, server[1]]
			break
	udp.close()
	return result


func _resolve(host_name: String) -> String:
	var id := IP.resolve_hostname_queue_item(host_name, IP.TYPE_IPV4)
	var deadline := Time.get_ticks_msec() + 1500
	while IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_WAITING and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ip := IP.get_resolve_item_address(id) if IP.get_resolve_item_status(id) == IP.RESOLVER_STATUS_DONE else ""
	IP.erase_resolve_item(id)
	return ip


## Host, every quarter second: sends hole-punching packets towards a joiner being let in, and keeps the NAT
## mapping the STUN server saw alive while nobody is in yet.
func _tick() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or enet.host == null or not is_host:
		return
	var now := Time.get_ticks_msec()
	if not _punch_target.is_empty() and _peer_id == 0 and now < _punch_until:
		enet.host.socket_send(_punch_target[0], _punch_target[1], "normandy-1944".to_utf8_buffer())
	if not _stun_server.is_empty() and _peer_id == 0 and now >= _next_keepalive:
		_next_keepalive = now + 15000
		enet.host.socket_send(_stun_server[0], _stun_server[1], Nat.stun_request(Crypto.new().generate_random_bytes(12)))


func remote_team() -> int:
	return 1 - local_team


## IPv4 addresses of this machine the other player could connect to.
static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			result.append(address)
	return result


## The password stretched into the key both sides prove they hold.
static func password_key(text: String) -> PackedByteArray:
	var key := ("normandy-1944/" + text).to_utf8_buffer()
	var hashing := HashingContext.new()
	for i in KEY_ROUNDS:
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(key)
		key = hashing.finish()
	return key


## Host only: tell the joined player which battle to build.
func send_setup(setup: Dictionary) -> void:
	_receive_setup.rpc_id(_remote_id(), setup)


func send_command(command: Dictionary, checksum: String) -> void:
	if active:
		_receive_command.rpc_id(_remote_id(), command, checksum)


## Waits for the opponent's next command. Returns {} if the session closes first.
func next_command() -> Dictionary:
	var session := _session
	while _queue.is_empty():
		await command_received
		if session != _session:
			return {}
	return _queue.pop_front()


## Host only: offer the joined player a saved game to continue (GameSession.online_offer). Answered by
## resume_started once both games hold the same battle, or by resume_declined, desynced or disconnected.
func send_resume(offer: Dictionary) -> void:
	_resume_checksum = offer["checksum"]
	_receive_resume.rpc_id(_remote_id(), offer)


## Joiner: we loaded the offered battle, and this is its checksum. The host checks it and says go.
func accept_resume(checksum: String) -> void:
	_resume_loaded.rpc_id(1, checksum)


## Joiner: we don't want to continue the offered game. Hangs up shortly after telling the host.
func decline_resume() -> void:
	active = false
	_resume_declined.rpc_id(1)
	var session := _session
	await get_tree().create_timer(0.5).timeout
	if session == _session:
		close()


## Called by whoever verified the opponent's command that changed the turn (or ended the battle): tells
## the opponent the state matched, and both sides emit turn_agreed so they can save it.
func agree_turn(turn_index: int, checksum: String) -> void:
	if active:
		_turn_agreed.rpc_id(_remote_id(), turn_index, checksum)
	turn_agreed.emit(turn_index, checksum)


## Tells both sides the games no longer match.
func report_desync(reason: String) -> void:
	if active:
		_peer_desynced.rpc_id(_remote_id(), reason)
	desynced.emit(reason)


func _remote_id() -> int:
	return _peer_id if is_host else 1


## True if the remote call being handled comes from the opponent we let in (or, joining, from the host
## after it proved the password).
func _from_opponent() -> bool:
	if is_host:
		return _peer_id != 0 and multiplayer.get_remote_sender_id() == _peer_id
	return _welcomed


func _proof(role: String, host_nonce: PackedByteArray, join_nonce: PackedByteArray) -> PackedByteArray:
	var message := role.to_utf8_buffer()
	message.append_array(host_nonce)
	message.append_array(join_nonce)
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _key, message)


## Compares two proofs in time that doesn't depend on where they differ.
static func _same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var difference := 0
	for i in a.size():
		difference |= a[i] ^ b[i]
	return difference == 0


## Host: tell a newcomer why it can't come in, then hang up on it.
func _turn_away(peer_id: int, reason: String) -> void:
	_pending.erase(peer_id)
	_refuse.rpc_id(peer_id, reason)
	var session := _session
	await get_tree().create_timer(0.5).timeout
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if session == _session and enet != null and enet.get_peer(peer_id) != null and peer_id != _peer_id:
		enet.disconnect_peer(peer_id)


# --- Remote calls ---
# Letting a player in: the joiner says hello with its version, the host answers with a nonce, the joiner
# proves the password over both nonces, and the host proves it back. Only then does the game start.

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: int) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _peer_id != 0:
		_turn_away(sender, "The host is already playing someone else.")
	elif now < _locked_until:
		_turn_away(sender, "Too many wrong passwords. Try again in a minute.")
	elif protocol != PROTOCOL:
		_turn_away(sender, "The other game is a different version.")
	else:
		var nonce := Crypto.new().generate_random_bytes(16)
		_pending[sender] = nonce
		_challenge.rpc_id(sender, nonce)
		var session := _session
		await get_tree().create_timer(AUTH_TIMEOUT).timeout
		if session == _session and _pending.get(sender) == nonce:
			_turn_away(sender, "Took too long to answer.")


@rpc("authority", "call_remote", "reliable")
func _challenge(host_nonce: PackedByteArray) -> void:
	var join_nonce := Crypto.new().generate_random_bytes(16)
	_join_nonces = [host_nonce, join_nonce]
	_answer.rpc_id(1, join_nonce, _proof("join", host_nonce, join_nonce))


@rpc("any_peer", "call_remote", "reliable")
func _answer(join_nonce: PackedByteArray, proof: PackedByteArray) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_host or not _pending.has(sender) or _peer_id != 0:
		return
	var host_nonce: PackedByteArray = _pending[sender]
	_pending.erase(sender)
	if not _same(proof, _proof("join", host_nonce, join_nonce)):
		var now := Time.get_ticks_msec() / 1000.0
		_failures = _failures.filter(func(t: float) -> bool: return now - t < LOCKOUT)
		_failures.append(now)
		if _failures.size() >= MAX_FAILURES:
			_locked_until = now + LOCKOUT
		_turn_away(sender, "Wrong password.")
		return
	_peer_id = sender
	active = true
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	enet.refuse_new_connections = true
	for other: int in _pending.keys():
		_turn_away(other, "The host is already playing someone else.")
	if enet.get_peer(sender) != null:
		opponent = enet.get_peer(sender).get_remote_address()
	_welcome.rpc_id(sender, _proof("host", host_nonce, join_nonce))
	peer_joined.emit()


@rpc("authority", "call_remote", "reliable")
func _welcome(proof: PackedByteArray) -> void:
	if _join_nonces.is_empty() or not _same(proof, _proof("host", _join_nonces[0], _join_nonces[1])):
		_fail("The host doesn't know the password.")
		return
	_welcomed = true


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _receive_setup(setup: Dictionary) -> void:
	if not _welcomed:
		return
	active = true
	setup_received.emit(setup)


@rpc("any_peer", "call_remote", "reliable")
func _receive_command(command: Dictionary, checksum: String) -> void:
	if not _from_opponent():
		return
	_queue.append({"command": command, "checksum": checksum})
	command_received.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_resume(offer: Dictionary) -> void:
	if not _welcomed:
		return
	active = true
	local_team = 1 - clampi(int(offer.get("team", 0)), 0, 1)
	resume_offered.emit(offer)


@rpc("any_peer", "call_remote", "reliable")
func _resume_loaded(checksum: String) -> void:
	if not is_host or not _from_opponent() or _resume_checksum == "":
		return
	if checksum != _resume_checksum:
		report_desync("The two games loaded different battles.")
		return
	_resume_checksum = ""
	_resume_start.rpc_id(_peer_id)
	resume_started.emit()


@rpc("authority", "call_remote", "reliable")
func _resume_start() -> void:
	if _welcomed:
		resume_started.emit()


@rpc("any_peer", "call_remote", "reliable")
func _resume_declined() -> void:
	if is_host and _from_opponent() and _resume_checksum != "":
		resume_declined.emit()


@rpc("any_peer", "call_remote", "reliable")
func _turn_agreed(turn_index: int, checksum: String) -> void:
	if _from_opponent():
		turn_agreed.emit(turn_index, checksum)


@rpc("any_peer", "call_remote", "reliable")
func _peer_desynced(reason: String) -> void:
	if _from_opponent():
		desynced.emit("The other game reports: " + reason)


# --- Connection events ---
# These arrive while the multiplayer peer is being polled, so the peer is only closed afterwards.

func _on_peer_connected(_id: int) -> void:
	pass


func _on_connected_to_server() -> void:
	_hello.rpc_id(1, PROTOCOL)


func _on_peer_disconnected(id: int) -> void:
	if is_host and id != _peer_id:
		# Someone who never got in.
		_pending.erase(id)
		return
	_lost_peer.call_deferred(active)


func _lost_peer(was_active: bool) -> void:
	close()
	if was_active:
		disconnected.emit()


## The host couldn't be reached. Over the internet keep trying for a while: the host may still be letting
## us in.
func _on_connection_failed() -> void:
	if not _join_target.is_empty() and Time.get_ticks_msec() < _join_deadline:
		_retry_join.call_deferred(_session)
		return
	_fail("")


func _retry_join(session: int) -> void:
	await get_tree().create_timer(1.0).timeout
	if session != _session or _join_target.is_empty():
		return
	multiplayer.multiplayer_peer.close()
	if _connect_to_host() != OK:
		_fail("")


## Gives up joining, saying why ("" if we don't know).
func _fail(reason: String) -> void:
	last_error = reason
	_join_target = []
	close.call_deferred()
	connection_failed.emit.call_deferred()
