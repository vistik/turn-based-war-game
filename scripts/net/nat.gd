class_name Nat
extends RefCounted
## Helpers for reaching the other player over the internet without a server of our own:
## - UPnP asks the host's router to forward the game port (many home routers allow it).
## - STUN asks a public STUN server which address and port the internet sees us at, so the players can
##   swap addresses ("hole punching": each side sends from the game's own port, which opens its NAT for
##   packets coming back from the other).
## Only the network packets are built and read here; Net does the sending and waiting.

## Public STUN servers, tried in turn. They only see a request and answer with our address.
const STUN_SERVERS := [["stun.l.google.com", 19302], ["stun.cloudflare.com", 3478], ["stun1.l.google.com", 19302]]
const STUN_COOKIE := 0x2112A442
## How long a router port mapping lasts, in seconds; it is removed when the game closes anyway.
const UPNP_LEASE := 4 * 3600
const UPNP_NAME := "Normandy 1944"


## A STUN Binding Request (RFC 5389) with the given 12-byte transaction id.
static func stun_request(transaction: PackedByteArray) -> PackedByteArray:
	var packet := PackedByteArray([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42])
	packet.append_array(transaction)
	return packet


## The address the STUN server saw in its answer to `transaction`, as "ip:port", or "" if `packet` isn't
## a successful answer to it.
static func stun_address(packet: PackedByteArray, transaction: PackedByteArray) -> String:
	if packet.size() < 20 or _u16(packet, 0) != 0x0101 or _u32(packet, 4) != STUN_COOKIE:
		return ""
	if packet.slice(8, 20) != transaction:
		return ""
	var end := mini(packet.size(), 20 + _u16(packet, 2))
	var at := 20
	var mapped := ""
	while at + 4 <= end:
		var kind := _u16(packet, at)
		var length := _u16(packet, at + 2)
		var value := at + 4
		if value + length > end:
			break
		# Only IPv4 (family 1). XOR-MAPPED-ADDRESS is preferred; plain MAPPED-ADDRESS is for old servers.
		if length >= 8 and packet[value + 1] == 0x01 and (kind == 0x0020 or kind == 0x0001):
			var port := _u16(packet, value + 2)
			var octets := packet.slice(value + 4, value + 8)
			if kind == 0x0020:
				port ^= STUN_COOKIE >> 16
				for i in 4:
					octets[i] ^= packet[4 + i]
				return "%d.%d.%d.%d:%d" % [octets[0], octets[1], octets[2], octets[3], port]
			mapped = "%d.%d.%d.%d:%d" % [octets[0], octets[1], octets[2], octets[3], port]
		at = value + ((length + 3) & ~3)
	return mapped


## Splits "host:port" (or just "host") into [host, port].
static func split_address(text: String, default_port: int) -> Array:
	text = text.strip_edges()
	if text.count(":") == 1:
		return [text.get_slice(":", 0), text.get_slice(":", 1).to_int()]
	return [text, default_port]


## True for addresses on the same network (private, loopback, link-local), where no NAT is in the way.
static func is_local(host: String) -> bool:
	if host == "localhost" or host.begins_with("127.") or host.begins_with("10.") or host.begins_with("192.168.") \
			or host.begins_with("169.254."):
		return true
	if host.begins_with("172."):
		var second := host.get_slice(".", 1).to_int()
		return second >= 16 and second <= 31
	# 100.64.0.0/10: carrier-grade NAT, and VPNs such as Tailscale.
	if host.begins_with("100."):
		var second := host.get_slice(".", 1).to_int()
		return second >= 64 and second <= 127
	return false


## Asks the router to forward UDP `port` to this computer. Blocks for a couple of seconds, so Net runs it
## on a thread. Returns {"upnp": UPNP, "address": the router's public address} or {} if it said no.
static func open_router_port(port: int) -> Dictionary:
	var upnp := UPNP.new()
	if upnp.discover(1500, 2) != UPNP.UPNP_RESULT_SUCCESS:
		return {}
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {}
	# Some routers only take permanent mappings.
	if upnp.add_port_mapping(port, port, UPNP_NAME, "UDP", UPNP_LEASE) != UPNP.UPNP_RESULT_SUCCESS \
			and upnp.add_port_mapping(port, port, UPNP_NAME, "UDP", 0) != UPNP.UPNP_RESULT_SUCCESS:
		return {}
	var address := upnp.query_external_address()
	if address == "":
		upnp.delete_port_mapping(port, "UDP")
		return {}
	return {"upnp": upnp, "address": "%s:%d" % [address, port]}


static func _u16(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 8) | bytes[at + 1]


static func _u32(bytes: PackedByteArray, at: int) -> int:
	return (_u16(bytes, at) << 16) | _u16(bytes, at + 2)
