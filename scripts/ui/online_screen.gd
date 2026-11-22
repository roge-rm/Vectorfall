class_name OnlineScreen
extends Control

signal closed

const SEARCH_MS := 1800

var address: LineEdit
var port: SpinBox
var report: Label
var join_button: Button
var find_button: Button
var found: VBoxContainer
var connection: OnlineClient
var search: PacketPeerUDP
var search_until := 0
var seen := {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var box := MenuKit.card(self, "Online play", 460.0)
	box.add_child(MenuKit.heading("Server address", 24))
	address = LineEdit.new()
	address.custom_minimum_size.y = MenuKit.px(40)
	var edit_frame := StyleBoxFlat.new()
	edit_frame.bg_color = InkUi.CREAM
	edit_frame.border_color = InkUi.INK
	edit_frame.set_border_width_all(MenuKit.pxi(2))
	edit_frame.set_content_margin_all(MenuKit.px(6))
	address.add_theme_stylebox_override("normal", edit_frame)
	address.add_theme_color_override("font_color", InkUi.INK)
	address.add_theme_color_override("font_placeholder_color", InkUi.BROWN_GREY)
	address.add_theme_color_override("caret_color", InkUi.INK)
	address.max_length = 256
	address.placeholder_text = "Server address or WebSocket URL"
	address.text = linked_server()
	address.text_submitted.connect(func(_text: String) -> void: _join())
	box.add_child(address)
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = MatchProtocol.GAME_PORT
	port.prefix = "UDP port "
	port.visible = not OS.has_feature("web")
	box.add_child(port)
	join_button = MenuKit.button("Join", _join, MenuKit.BUTTON_SIZE, true)
	box.add_child(join_button)
	find_button = MenuKit.button("Find LAN games", _find, MenuKit.BUTTON_SIZE)
	find_button.visible = not OS.has_feature("web")
	box.add_child(find_button)
	found = VBoxContainer.new()
	box.add_child(found)
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(report)
	box.add_child(MenuKit.button("Back", _back, MenuKit.BUTTON_SIZE))


static func linked_server() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
		"new URLSearchParams(location.search).get('server') || ''")).strip_edges()


func open() -> void:
	show()
	report.text = OnlineClient.last_error
	OnlineClient.last_error = ""
	if OS.has_feature("mobile"):
		join_button.grab_focus()
	else:
		address.grab_focus()


func _join() -> void:
	if is_instance_valid(connection):
		return
	var target := address.text.strip_edges()
	if target.is_empty():
		report.text = "Enter a server address."
		return
	var websocket := target.begins_with("ws://") or target.begins_with("wss://")
	if OS.has_feature("web") and not websocket:
		report.text = "Enter a ws:// or wss:// address."
		return
	_stop_search()
	report.text = "Connecting…"
	join_button.disabled = true
	connection = OnlineClient.new()
	get_tree().root.add_child(connection)
	connection.failed.connect(_failed)
	connection.ready_to_play.connect(_load_match.bind(connection, get_tree()))
	var result := connection.start(target, int(port.value), websocket)
	if result != OK:
		connection.stop()
		connection = null
		_failed("Could not connect: " + error_string(result))


static func _load_match(client: OnlineClient, tree: SceneTree) -> void:
	OnlineClient.active = client
	tree.change_scene_to_file.call_deferred("res://scenes/main.tscn")


func _failed(reason: String) -> void:
	connection = null
	report.text = reason
	join_button.disabled = false


func _back() -> void:
	_stop_search()
	if is_instance_valid(connection) and not connection.started:
		connection.stop()
	connection = null
	join_button.disabled = false
	closed.emit()


func _find() -> void:
	_stop_search()
	for button in found.get_children():
		button.queue_free()
	seen.clear()
	search = PacketPeerUDP.new()
	if search.bind(0) != OK:
		report.text = "Could not start LAN search."
		_stop_search()
		return
	search.set_broadcast_enabled(true)
	search.set_dest_address("255.255.255.255", MatchProtocol.DISCOVERY_PORT)
	search.put_packet(MatchProtocol.DISCOVERY_QUERY.to_ascii_buffer())
	search.set_dest_address("127.0.0.1", MatchProtocol.DISCOVERY_PORT)
	search.put_packet(MatchProtocol.DISCOVERY_QUERY.to_ascii_buffer())
	search_until = Time.get_ticks_msec() + SEARCH_MS
	report.text = "Looking for LAN games…"


func _process(_delta: float) -> void:
	if search == null:
		return
	for index in 16:
		if search.get_available_packet_count() == 0:
			break
		var packet := search.get_packet()
		var ip := search.get_packet_ip()
		if packet.size() > 512:
			continue
		var reply: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not reply is Dictionary or not reply.get("name") is String or not reply.get("port") is float:
			continue
		var game_port := clampi(int(reply.port), 1, 65535)
		var key := "%s:%d" % [ip, game_port]
		if seen.has(key) or seen.size() >= 3:
			continue
		seen[key] = true
		found.add_child(MenuKit.button(reply.name.left(40), _select.bind(ip, game_port), 22))
	if Time.get_ticks_msec() > search_until:
		report.text = "No LAN games found." if seen.is_empty() else ""
		_stop_search()


func _select(ip: String, game_port: int) -> void:
	address.text = ip
	port.value = game_port
	_join()


func _stop_search() -> void:
	if search != null:
		search.close()
		search = null
