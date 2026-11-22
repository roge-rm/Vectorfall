class_name OnlineScreen
extends Control

signal closed

var address: LineEdit
var port: SpinBox
var report: Label
var join_button: Button
var browse_button: Button
var direct: Control
var browser: ServerBrowser
var connection: OnlineClient


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	direct = Control.new()
	direct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(direct)
	var box := MenuKit.card(direct, "Online play", 460.0)
	box.add_child(MenuKit.heading("Server address", 24))
	address = MenuKit.line_edit("Server address or WebSocket URL")
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
	browse_button = MenuKit.button("Browse servers", _browse, MenuKit.BUTTON_SIZE)
	box.add_child(browse_button)
	report = Label.new()
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(report)
	box.add_child(MenuKit.button("Back", _back, MenuKit.BUTTON_SIZE, true))
	browser = ServerBrowser.new()
	browser.hide()
	browser.closed.connect(_close_browser)
	browser.selected.connect(_select)
	add_child(browser)


static func linked_server() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
		"new URLSearchParams(location.search).get('server') || ''")).strip_edges()


func open() -> void:
	show()
	direct.show()
	browser.hide()
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
	if is_instance_valid(connection) and not connection.started:
		connection.stop()
	connection = null
	join_button.disabled = false
	closed.emit()


func _browse() -> void:
	direct.hide()
	browser.open()


func _close_browser() -> void:
	browser.stop()
	browser.hide()
	direct.show()
	browse_button.grab_focus()


func _select(host: String, game_port: int) -> void:
	_close_browser()
	address.text = host
	port.value = game_port
	_join()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_cancel"):
		return
	if browser.visible:
		_close_browser()
	else:
		_back()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and browser != null and is_visible_in_tree():
		if browser.visible:
			_close_browser()
		else:
			_back()
