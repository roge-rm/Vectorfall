class_name ServerBrowser
extends Control

signal selected(host: String, port: int)
signal closed

const WAIT_MS := 1800
const MAX_PROBES := 4
const PREFS := "user://server-browser.cfg"

var directory: LineEdit
var report: Label
var refresh: Button
var rows: VBoxContainer
var request: HTTPRequest
var lan: PacketPeerUDP
var sent := 0
var seen := {}
var pending: Array[Dictionary] = []
var probes: Array[Dictionary] = []
var fetching := false
var directory_failed := false
var invalid_directory := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := MenuKit.screen(self, "Server browser")
	var actions := MenuKit.button_row(page)
	directory = MenuKit.line_edit("Directory URL (optional)")
	directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	directory.text = _saved_directory()
	directory.text_submitted.connect(func(_url: String) -> void: _scan())
	actions.add_child(directory)
	refresh = MenuKit.button("Refresh", _scan, 22)
	actions.add_child(refresh)
	report = MenuKit.ink_label("", 15)
	page.add_child(report)
	rows = MenuKit.rows(page)
	var buttons := MenuKit.button_row(page)
	buttons.add_child(MenuKit.button("Back", _back, MenuKit.BUTTON_SIZE, true))
	request = HTTPRequest.new()
	request.timeout = 5.0
	request.max_redirects = 0
	request.body_size_limit = ServerDirectory.BODY_LIMIT
	add_child(request)
	request.request_completed.connect(_directory_reply)


static func _saved_directory() -> String:
	var file := ConfigFile.new()
	if file.load(PREFS) == OK:
		return str(file.get_value("servers", "directory", ""))
	return str(ProjectSettings.get_setting("skifrei/directory/url", ""))


func open() -> void:
	show()
	refresh.grab_focus()
	_scan()


func _scan() -> void:
	stop()
	for row in rows.get_children():
		rows.remove_child(row)
		row.queue_free()
	seen.clear()
	directory_failed = false
	var target := ServerDirectory.url(directory.text)
	invalid_directory = not directory.text.strip_edges().is_empty() and target.is_empty()
	if not invalid_directory and target != _saved_directory():
		var saved := ConfigFile.new()
		saved.set_value("servers", "directory", target)
		saved.save(PREFS)
	if not target.is_empty():
		fetching = request.request(target) == OK
		directory_failed = not fetching
	if not OS.has_feature("web"):
		lan = PacketPeerUDP.new()
		if lan.bind(0) == OK:
			sent = Time.get_ticks_msec()
			lan.set_broadcast_enabled(true)
			for ip in ["255.255.255.255", "127.0.0.1"]:
				lan.set_dest_address(ip, MatchProtocol.DISCOVERY_PORT)
				lan.put_packet(MatchProtocol.DISCOVERY_QUERY.to_ascii_buffer())
		else:
			lan = null
	_update_report()


func _directory_reply(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	fetching = false
	directory_failed = result != HTTPRequest.RESULT_SUCCESS or code != 200
	if not directory_failed:
		pending = ServerDirectory.entries(body, OS.has_feature("web"))
	_update_report()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var now := Time.get_ticks_msec()
	if lan != null:
		for index in 16:
			if lan.get_available_packet_count() == 0:
				break
			var packet := lan.get_packet()
			if packet.size() > 512:
				continue
			var data: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if data is Dictionary:
				var entry := ServerDirectory.status(data)
				if not entry.is_empty():
					_add(entry, lan.get_packet_ip(), now - sent, "LAN")
		if now - sent >= WAIT_MS:
			lan.close()
			lan = null
	for probe in probes.duplicate():
		_poll_probe(probe)
		if probe.get("done", false) or now - probe.sent >= WAIT_MS:
			var entry: Dictionary = probe.entry
			var live: Dictionary = probe.get("live", {})
			if not live.is_empty():
				live.port = entry.port
				entry = live
			_add(entry, probe.get("address", probe.host), probe.get("ping", -1), "Public")
			_close_probe(probe)
			probes.erase(probe)
	while probes.size() < MAX_PROBES and not pending.is_empty():
		_start_probe(pending.pop_front())
	_update_report()


func _start_probe(entry: Dictionary) -> void:
	var websocket: bool = OS.has_feature("web") or entry.host.is_empty()
	var host: String = entry.ws if websocket else entry.host
	var probe := {"host": host, "entry": entry, "sent": Time.get_ticks_msec()}
	probes.append(probe)
	if websocket or host.is_valid_ip_address():
		_connect_probe(probe, host, websocket)
	else:
		var query := IP.resolve_hostname_queue_item(host)
		if query == IP.RESOLVER_INVALID_ID:
			probe["done"] = true
		else:
			probe["query"] = query


func _poll_probe(probe: Dictionary) -> void:
	if probe.has("link"):
		probe.link.poll()
	elif probe.has("query"):
		var query: int = probe.query
		match IP.get_resolve_item_status(query):
			IP.RESOLVER_STATUS_DONE:
				var address := IP.get_resolve_item_address(query)
				IP.erase_resolve_item(query)
				probe.erase("query")
				_connect_probe(probe, address, false)
			IP.RESOLVER_STATUS_ERROR:
				probe["done"] = true


func _connect_probe(probe: Dictionary, address: String, websocket: bool) -> void:
	var link := MatchTransport.new()
	if address.is_empty() or link.connect_to(address, probe.entry.port, websocket) != OK:
		link.close()
		probe["done"] = true
		return
	probe["link"] = link
	probe["address"] = address
	link.joined.connect(func(id: int) -> void:
		probe["started"] = Time.get_ticks_msec()
		probe.link.send(id, MatchProtocol.encode({"kind": "browse"}), 0, true))
	link.left.connect(func(_id: int) -> void: probe["done"] = true)
	link.received.connect(func(_id: int, packet: PackedByteArray) -> void:
		var reply := MatchProtocol.decode(packet, MatchProtocol.INPUT_MAX)
		if reply.get("kind") != "browse" or not reply.get("server") is Dictionary:
			return
		var live := ServerDirectory.status(reply.server)
		if not live.is_empty():
			probe["live"] = live
			probe["ping"] = Time.get_ticks_msec() - probe.get("started", probe.sent)
			probe["done"] = true)


func _close_probe(probe: Dictionary) -> void:
	if probe.has("query"):
		IP.erase_resolve_item(probe.query)
	if probe.has("link"):
		probe.link.close()
		# The signal callbacks capture the probe dictionary.
		probe.erase("link")


func _add(entry: Dictionary, host: String, ping: int, origin: String) -> void:
	var key := [host, entry.port]
	if seen.has(key) or seen.size() >= ServerDirectory.LIMIT:
		return
	seen[key] = true
	var row := HBoxContainer.new()
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	var name := MenuKit.ink_label(entry.name, 20, InkUi.Face.BLACK)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(name)
	var mode := "Capture and Hold" if entry.mode == "hold" else "CTF"
	var latency := "%d ms" % ping if ping >= 0 else "Ping unavailable"
	var details := MenuKit.ink_label("%s · %s · %d/%d players · %s · %s" % [
		entry.map, mode, entry.players, entry.slots, latency, origin])
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	labels.add_child(details)
	row.add_child(MenuKit.button("Join", func() -> void: selected.emit(host, entry.port), 19))
	rows.add_child(row)


func _update_report() -> void:
	if fetching or lan != null or not probes.is_empty() or not pending.is_empty():
		report.text = "Looking for servers…"
	elif invalid_directory:
		report.text = "Enter an HTTPS directory URL."
	elif directory_failed:
		report.text = "Could not reach the directory."
	elif seen.is_empty():
		report.text = "No servers found." if not directory.text.is_empty() or not OS.has_feature("web") else "Enter a directory URL."
	else:
		report.text = "%d servers found" % seen.size() if seen.size() != 1 else "1 server found"


func _back() -> void:
	closed.emit()


func stop() -> void:
	request.cancel_request()
	fetching = false
	if lan != null:
		lan.close()
		lan = null
	pending.clear()
	for probe in probes:
		_close_probe(probe)
	probes.clear()


func _exit_tree() -> void:
	stop()
