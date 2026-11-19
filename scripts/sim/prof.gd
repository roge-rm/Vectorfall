class_name Prof
extends RefCounted

## A per tick profiler for tools/bot-match.sh --profile. Off, each timed spot
## costs one static read. On, add() sums microseconds and count() sums calls
## for the tick, and end_tick() keeps the tick's totals. add() and count()
## may be called from bot threads; the rest is main thread only.

static var on := false
## Part name to its time this tick, in microseconds.
static var _now := {}
## Counter name to its count this tick.
static var _counts := {}
## "t:part" or "n:counter" to an Array with one int per tick.
static var series := {}
static var ticks := 0
static var _lock := Mutex.new()


## Only kept on the main thread: from bot threads the lock would be fought
## over and the times would show the waiting. Time the bot parts with
## tools/bot-match.sh --serial-bots.
static func add(part: String, usec: int) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	_now[part] = int(_now.get(part, 0)) + usec


static func count(what: String, n := 1) -> void:
	_lock.lock()
	_counts[what] = int(_counts.get(what, 0)) + n
	_lock.unlock()


## Keeps this tick's totals; parts and counters not seen this tick get 0.
static func end_tick() -> void:
	for key: String in _now:
		_start("t:" + key)
	for key: String in _counts:
		_start("n:" + key)
	for key: String in series:
		var name := key.substr(2)
		var values: Array = series[key]
		values.append(_now.get(name, 0) if key.begins_with("t:") else _counts.get(name, 0))
	ticks += 1
	_now.clear()
	_counts.clear()


## A series first seen now, with 0 for the ticks before.
static func _start(key: String) -> void:
	if not series.has(key):
		var values := []
		values.resize(ticks)
		values.fill(0)
		series[key] = values


## mean, p95, max and sum of a part ("t:name") or counter ("n:name") over
## every tick.
static func stats(key: String) -> Dictionary:
	var values: Array = series.get(key, []).duplicate()
	if values.is_empty():
		return { "mean": 0.0, "p95": 0, "max": 0, "sum": 0 }
	var sum := 0
	for v: int in values:
		sum += v
	values.sort()
	var n := values.size()
	return { "mean": float(sum) / n, "p95": values[mini(int(n * 0.95), n - 1)], "max": values[n - 1], "sum": sum }
