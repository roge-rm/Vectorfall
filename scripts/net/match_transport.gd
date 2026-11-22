class_name MatchTransport
extends RefCounted

signal joined(id: int)
signal left(id: int)
signal received(id: int, packet: PackedByteArray)

const CHANNELS := 3
const PEERS := MatchProtocol.MAX_TEAM_SIZE * 2
const TIMEOUT_MS := 12000

var enet: ENetConnection
var listener: TCPServer
var peers: Dictionary[int, ENetPacketPeer] = {}
var sockets: Dictionary[int, WebSocketPeer] = {}
var connecting: Dictionary[int, int] = {}
var serial := 1
var host := false
var _client_web_joined := false


func listen(game_port: int, web_port: int) -> Error:
	host = true
	enet = ENetConnection.new()
	var err := enet.create_host_bound("*", game_port, PEERS, CHANNELS)
	if err != OK:
		return err
	listener = TCPServer.new()
	err = listener.listen(web_port)
	if err != OK:
		close()
	return err


func connect_to(address: String, port: int, websocket: bool) -> Error:
	if websocket:
		var socket := _socket()
		sockets[1] = socket
		return socket.connect_to_url(address)
	enet = ENetConnection.new()
	var error := enet.create_host(1, CHANNELS)
	if error != OK:
		return error
	var peer := enet.connect_to_host(address, port, CHANNELS)
	return OK if peer != null else ERR_CANT_CONNECT


func _socket() -> WebSocketPeer:
	var socket := WebSocketPeer.new()
	socket.inbound_buffer_size = 2 * MatchProtocol.SNAPSHOT_MAX if not host else 16384
	socket.outbound_buffer_size = 2 * MatchProtocol.SNAPSHOT_MAX
	socket.max_queued_packets = 64
	return socket


func poll() -> void:
	if enet != null:
		for index in 256:
			if enet == null:
				return
			var event := enet.service(0)
			var kind: int = event[0]
			if kind == ENetConnection.EVENT_NONE or kind == ENetConnection.EVENT_ERROR:
				break
			var peer: ENetPacketPeer = event[1]
			if kind == ENetConnection.EVENT_CONNECT:
				var id := serial if host else 1
				serial += 1
				peers[id] = peer
				peer.set_timeout(0, 3000, TIMEOUT_MS)
				peer.set_meta("link_id", id)
				joined.emit(id)
			elif peer != null and peer.has_meta("link_id"):
				var id: int = peer.get_meta("link_id")
				if kind == ENetConnection.EVENT_DISCONNECT:
					peers.erase(id)
					left.emit(id)
				elif kind == ENetConnection.EVENT_RECEIVE:
					received.emit(id, peer.get_packet())
	if listener != null:
		for index in 16:
			if not listener.is_connection_available():
				break
			var stream := listener.take_connection()
			if sockets.size() >= PEERS:
				stream.disconnect_from_host()
				continue
			var socket := _socket()
			if socket.accept_stream(stream) != OK:
				continue
			connecting[serial] = Time.get_ticks_msec()
			sockets[serial] = socket
			serial += 1
	for id: int in sockets.keys():
		var socket := sockets[id]
		socket.poll()
		match socket.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				if connecting.has(id) or (not host and not _client_web_joined):
					connecting.erase(id)
					_client_web_joined = true
					joined.emit(id)
				for index in 64:
					if not sockets.has(id) or socket.get_available_packet_count() == 0:
						break
					received.emit(id, socket.get_packet())
			WebSocketPeer.STATE_CLOSED:
				sockets.erase(id)
				connecting.erase(id)
				left.emit(id)
			WebSocketPeer.STATE_CONNECTING:
				if host and Time.get_ticks_msec() - connecting.get(id, 0) > TIMEOUT_MS:
					sockets.erase(id)
					connecting.erase(id)


func send(id: int, packet: PackedByteArray, channel: int, reliable := false) -> void:
	if peers.has(id):
		var flags := ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
		peers[id].send(channel, packet, flags)
	elif sockets.has(id):
		var socket := sockets[id]
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			# An old snapshot is disposable when TCP is backed up.
			if reliable or socket.get_current_outbound_buffered_amount() < MatchProtocol.SNAPSHOT_MAX:
				socket.put_packet(packet)


func disconnect_peer(id: int) -> void:
	if peers.has(id):
		peers[id].peer_disconnect()
	if sockets.has(id):
		sockets[id].close()


func close() -> void:
	if enet != null:
		if not host:
			for peer in peers.values():
				peer.peer_disconnect_now()
		enet.destroy()
		enet = null
	if listener != null:
		listener.stop()
		listener = null
	for socket in sockets.values():
		socket.close()
	peers.clear()
	sockets.clear()
	connecting.clear()
