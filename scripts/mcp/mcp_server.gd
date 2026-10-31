class_name McpServer
extends RefCounted
## A small Model Context Protocol server (Streamable HTTP transport, JSON responses only) for the agent link.
## JSON-RPC 2.0 requests arrive as HTTP POSTs to /mcp; each gets one JSON reply and the connection closes.
## No server-sent event stream: GET /mcp answers 405, which the spec allows.
##
## Listens on 127.0.0.1 only and requires the session token, as "Authorization: Bearer <token>" (or
## "?token=" in the URL for clients that can't set headers). Requests from web pages (an Origin header
## that isn't localhost) are refused, so a browser tab can't reach the game.
## Never blocks: call poll() every frame; it reads and answers whatever has arrived.
##
## Tools come from a provider object with tool_list() -> Array of {name, description, inputSchema},
## call_tool(name, arguments) -> {"result": Variant} or {"error": String}, and instructions() -> String.
## A tool that has to wait for the game (a move playing out, the other side's turn) returns
## {"wait": Callable} instead; the callable is asked every poll and returns null until it has the outcome.
## The connection stays open meanwhile, so the agent simply gets a slower answer.

const PROTOCOL_VERSIONS := ["2025-06-18", "2025-03-26", "2024-11-05"]
const SERVER_NAME := "normandy-1944"
const SERVER_VERSION := "1.0.0"
const ENDPOINT := "/mcp"
## Requests bigger than this, or slower than the timeout, are dropped.
const MAX_REQUEST_BYTES := 1 << 20
const TIMEOUT_MSEC := 10000
## handle_http's status for a tool call that is still waiting; its second element is {"id", "wait"}.
const PENDING := -1
## Requests answered per poll(), to keep the frame rate up when an agent sends a burst.
const MAX_PER_POLL := 4

var tools: Object
var token := ""
var port := 0
## Called with each JSON-RPC method name, for the in-game activity line.
var on_request: Callable

var _server := TCPServer.new()
## Open connections: {"peer": StreamPeerTCP, "in": PackedByteArray, "out": PackedByteArray, "since": msec}.
var _clients: Array[Dictionary] = []


func _init(p_tools: Object, p_token: String) -> void:
	tools = p_tools
	token = p_token


func start(p_port: int) -> Error:
	stop()
	var err := _server.listen(p_port, "127.0.0.1")
	if err == OK:
		port = _server.get_local_port()
	return err


func stop() -> void:
	for client in _clients:
		client["peer"].disconnect_from_host()
	_clients.clear()
	_server.stop()


func is_listening() -> bool:
	return _server.is_listening()


func url() -> String:
	return "http://127.0.0.1:%d%s" % [port, ENDPOINT]


func poll() -> void:
	if not _server.is_listening():
		return
	while _server.is_connection_available() and _clients.size() < 16:
		_clients.append({"peer": _server.take_connection(), "in": PackedByteArray(), "out": PackedByteArray(), "since": Time.get_ticks_msec(), "done": false})
	var answered := 0
	for client in _clients.duplicate():
		var peer: StreamPeerTCP = client["peer"]
		peer.poll()
		var status := peer.get_status()
		# A waiting tool keeps its connection; the tool itself gives up in time.
		var timed_out: bool = Time.get_ticks_msec() - client["since"] > TIMEOUT_MSEC and not client.has("pending")
		if status != StreamPeerTCP.STATUS_CONNECTED or timed_out:
			peer.disconnect_from_host()
			_clients.erase(client)
			continue
		if not client["out"].is_empty():
			_flush(client)
			continue
		if client["done"]:
			peer.disconnect_from_host()
			_clients.erase(client)
			continue
		if client.has("pending"):
			var pending: Dictionary = client["pending"]
			var outcome: Variant = pending["wait"].call()
			if outcome != null:
				client.erase("pending")
				_reply(client, 200, {"Content-Type": "application/json"}, JSON.stringify(_tool_reply(pending["id"], outcome)))
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk: Array = peer.get_partial_data(available)
			if chunk[0] == OK:
				client["in"].append_array(chunk[1])
		if client["in"].size() > MAX_REQUEST_BYTES:
			_reply(client, 413, {}, "Request too large")
			continue
		if answered >= MAX_PER_POLL:
			continue
		var request := parse_http(client["in"])
		if request.is_empty():
			continue
		answered += 1
		var response := handle_http(request)
		if response[0] == PENDING:
			client["pending"] = response[1]
			client["in"] = PackedByteArray()
			continue
		_reply(client, response[0], response[1], response[2])


## Parses one HTTP/1.1 request from raw bytes: {"method", "path", "query", "headers" (lower-case keys), "body"},
## or {} while it's still incomplete.
static func parse_http(data: PackedByteArray) -> Dictionary:
	var text_end := -1
	for i in range(0, data.size() - 3):
		if data[i] == 13 and data[i + 1] == 10 and data[i + 2] == 13 and data[i + 3] == 10:
			text_end = i
			break
	if text_end == -1:
		return {}
	var lines := data.slice(0, text_end).get_string_from_utf8().split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 2:
		return {"method": "", "path": "", "query": {}, "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	var body_start := text_end + 4
	if data.size() - body_start < length:
		return {}
	var target := request_line[1]
	var query := {}
	var question := target.find("?")
	if question != -1:
		for pair in target.substr(question + 1).split("&", false):
			var parts := pair.split("=")
			query[parts[0].uri_decode()] = parts[1].uri_decode() if parts.size() > 1 else ""
		target = target.substr(0, question)
	return {
		"method": request_line[0], "path": target, "query": query, "headers": headers,
		"body": data.slice(body_start, body_start + length).get_string_from_utf8(),
	}


## Answers a parsed HTTP request: [status code, extra headers, body text].
func handle_http(request: Dictionary) -> Array:
	var headers: Dictionary = request["headers"]
	var origin: String = headers.get("origin", "")
	if origin != "" and not (origin.begins_with("http://127.0.0.1") or origin.begins_with("http://localhost")):
		return [403, {}, "Forbidden origin"]
	var host: String = headers.get("host", "127.0.0.1").get_slice(":", 0)
	if host not in ["127.0.0.1", "localhost"]:
		return [403, {}, "Forbidden host"]
	if request["path"] != ENDPOINT:
		return [404, {}, "Not found: the MCP endpoint is %s" % ENDPOINT]
	if not _authorized(request):
		return [401, {}, "Missing or wrong token. Send \"Authorization: Bearer <token>\" with the token shown in the game."]
	match request["method"]:
		"POST":
			pass
		"DELETE":
			return [200, {}, ""]
		_:
			return [405, {"Allow": "POST, DELETE"}, "Only POST: this server sends no event stream"]
	if headers.get("transfer-encoding", "") != "":
		return [411, {}, "Send a Content-Length"]
	var message: Variant = JSON.parse_string(request["body"])
	if message == null:
		return [400, {"Content-Type": "application/json"}, JSON.stringify(_error(null, -32700, "Parse error"))]
	var reply: Variant
	if message is Array:
		var replies := []
		for item: Variant in message:
			var one: Variant = handle_rpc(item)
			if one is Dictionary and one.has("wait"):
				one = _tool_reply(one["id"], {"error": "Tools that wait can't be called in a batch"})
			if one != null:
				replies.append(one)
		reply = replies if not replies.is_empty() else null
	else:
		reply = handle_rpc(message)
		if reply is Dictionary and reply.has("wait"):
			return [PENDING, reply, ""]
	if reply == null:
		return [202, {}, ""]
	return [200, {"Content-Type": "application/json"}, JSON.stringify(reply)]


## Handles one JSON-RPC message. Returns the response, or null for notifications and responses.
func handle_rpc(message: Variant) -> Variant:
	if not message is Dictionary or message.get("jsonrpc") != "2.0":
		return _error(null, -32600, "Invalid request")
	if not message.has("method"):
		return null
	var method: String = str(message["method"])
	if not message.has("id"):
		return null
	var id: Variant = message["id"]
	if id is float and id == floorf(id):
		id = int(id)
	var params: Dictionary = message.get("params", {}) if message.get("params", {}) is Dictionary else {}
	if on_request.is_valid():
		on_request.call(method if method != "tools/call" else "tools/call %s" % params.get("name", "?"))
	match method:
		"initialize":
			var wanted: String = str(params.get("protocolVersion", PROTOCOL_VERSIONS[0]))
			return _result(id, {
				"protocolVersion": wanted if wanted in PROTOCOL_VERSIONS else PROTOCOL_VERSIONS[0],
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": SERVER_NAME, "title": "Normandy 1944", "version": SERVER_VERSION},
				"instructions": tools.instructions(),
			})
		"ping":
			return _result(id, {})
		"tools/list":
			return _result(id, {"tools": tools.tool_list()})
		"tools/call":
			var name: Variant = params.get("name")
			var arguments: Variant = params.get("arguments", {})
			if not name is String or not arguments is Dictionary:
				return _error(id, -32602, "tools/call needs a name and an arguments object")
			var known := false
			for spec: Dictionary in tools.tool_list():
				known = known or spec["name"] == name
			if not known:
				return _error(id, -32602, "Unknown tool: %s" % name)
			var outcome: Dictionary = tools.call_tool(name, arguments)
			if outcome.has("wait"):
				return {"id": id, "wait": outcome["wait"]}
			return _tool_reply(id, outcome)
	return _error(id, -32601, "Method not found: %s" % method)


func _tool_reply(id: Variant, outcome: Dictionary) -> Dictionary:
	if outcome.has("error"):
		return _result(id, {"content": [{"type": "text", "text": str(outcome["error"])}], "isError": true})
	return _result(id, {"content": [{"type": "text", "text": JSON.stringify(outcome["result"])}], "isError": false})


func _authorized(request: Dictionary) -> bool:
	var given: String = request["headers"].get("authorization", "")
	if given.begins_with("Bearer "):
		given = given.substr(7).strip_edges()
	else:
		given = request["query"].get("token", "")
	return token != "" and given == token


func _result(id: Variant, result: Variant) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


func _error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


func _reply(client: Dictionary, status: int, headers: Dictionary, body: String) -> void:
	var reasons := {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
			405: "Method Not Allowed", 411: "Length Required", 413: "Payload Too Large"}
	var bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\n" % [status, reasons.get(status, "Error")]
	if not headers.has("Content-Type") and not bytes.is_empty():
		headers["Content-Type"] = "text/plain; charset=utf-8"
	for key: String in headers:
		head += "%s: %s\r\n" % [key, headers[key]]
	head += "Content-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" % bytes.size()
	client["out"] = head.to_utf8_buffer() + bytes
	client["in"] = PackedByteArray()
	client["done"] = true
	_flush(client)


func _flush(client: Dictionary) -> void:
	var peer: StreamPeerTCP = client["peer"]
	var sent: Array = peer.put_partial_data(client["out"])
	if sent[0] == OK:
		client["out"] = client["out"].slice(sent[1])
