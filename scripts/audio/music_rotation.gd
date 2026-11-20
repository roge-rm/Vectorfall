class_name MusicRotation
extends AudioStreamPlayer

## One stream at a time, across the menu and matches.

const TRACKS: Array[String] = [
	"first-light", "saltwake", "night-shift", "copper-ascent", "low-orbit",
	"wrong-side-of-the-rim", "coast-signal", "dead-frequency", "horizon-run", "home-signal",
]

var _rng := RandomNumberGenerator.new()
var _order: Array[int] = []
var _last := -1
var _audible := false


func _ready() -> void:
	_rng.randomize()
	finished.connect(_play_next)
	set_audible(_audible)


static func track_path(index: int) -> String:
	return "res://art/music/%s.ogg" % TRACKS[index]


func set_audible(on: bool) -> void:
	_audible = on
	if not is_node_ready():
		return
	stream_paused = not on
	if on and not playing:
		_play_next()


## Plays all ten once before shuffling again. Adjacent cycles also differ.
func next_index() -> int:
	if _order.is_empty():
		for k in TRACKS.size():
			_order.append(k)
		for k in range(_order.size() - 1, 0, -1):
			var pick := _rng.randi_range(0, k)
			var swap := _order[k]
			_order[k] = _order[pick]
			_order[pick] = swap
		if _order.back() == _last:
			_order[-1] = _order[0]
			_order[0] = _last
	_last = _order.pop_back()
	return _last


func _play_next() -> void:
	if not _audible:
		return
	stream = load(track_path(next_index())) as AudioStreamOggVorbis
	if stream != null:
		stream_paused = false
		play()
