class_name AdvisorSettings
extends RefCounted
## Player settings for move suggestions and the agent link (the MCP server), stored in user://advisor.cfg.
## Static so they survive scene changes. Everything that lets an outside program in is off by default.
## (Small on purpose: these keys can move into a shared settings store later.)

const PATH := "user://advisor.cfg"
const DEFAULT_PORT := 24945

## Run the MCP server while a battle is open, so an agent (Claude Code, Claude Desktop...) can help.
static var mcp_enabled := false
static var mcp_port := DEFAULT_PORT
## Let the agent make moves for the player through the execute_command tool. Never in online games.
static var agent_may_act := false
## Allow suggestions (the Suggest button and the agent link's read-only tools) in online games too.
static var help_online := false
## The agent link's bearer token for this run of the game. A new one each time the game starts.
static var session_token := ""

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	mcp_enabled = config.get_value("advisor", "mcp_enabled", false)
	mcp_port = config.get_value("advisor", "mcp_port", DEFAULT_PORT)
	agent_may_act = config.get_value("advisor", "agent_may_act", false)
	help_online = config.get_value("advisor", "help_online", false)


static func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("advisor", "mcp_enabled", mcp_enabled)
	config.set_value("advisor", "mcp_port", mcp_port)
	config.set_value("advisor", "agent_may_act", agent_may_act)
	config.set_value("advisor", "help_online", help_online)
	config.save(PATH)


## The bearer token an agent must send, made on first use.
static func token() -> String:
	if session_token == "":
		var crypto := Crypto.new()
		session_token = crypto.generate_random_bytes(16).hex_encode()
	return session_token
