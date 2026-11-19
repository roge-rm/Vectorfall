class_name SoundBank
extends RefCounted

## Every sound in the game, made by code once at load as 16 bit mono
## AudioStreamWAVs: shots and blasts for every weapon, hit markers, the jet and ski loops,
## footsteps, flag jingles, UI clicks and the bots' robot voices. Nothing is
## made while playing. Noise comes from fixed seeds, so the sounds are the
## same every run.

const RATE := 22050
const VOICE_RATE := 16000
## Every effect name get() knows.
const NAMES: Array[String] = ["disc_fire", "disc_blast", "chaingun", "grenade_fire", "grenade_blast", "mortar_fire", "mortar_blast", "plasma_fire", "plasma_hit", "sniper_fire", "blaster_fire", "blaster_hit", "throw", "hand_grenade_blast", "mine_place", "mine_arm", "mine_blast", "pack_on", "pack_off", "repair", "shield_hit", "hit", "kill", "jet", "ski", "step", "land", "flag_grab", "flag_alarm", "flag_dropped", "flag_returned", "flag_captured", "flag_lost", "click", "back"]
## Vowel formants in Hz (first, second) for the robot voices.
const VOWELS: Array[Vector2] = [Vector2(780, 1250), Vector2(520, 1850), Vector2(320, 2250), Vector2(520, 900), Vector2(350, 760)]
## Robot voice pitch in Hz per team: team 0 low and buzzy, team 1 higher and hollow.
const VOICE_PITCH: Array[float] = [105.0, 160.0]
const SYLLABLES := 12

static var _streams: Dictionary[String, AudioStreamWAV] = {}
## Line voices by line * 2 + team.
static var _voices: Dictionary[int, AudioStreamWAV] = {}
## Milliseconds the last build took.
static var build_ms := 0.0


## Makes everything, the first time it's called.
static func build() -> void:
	if not _streams.is_empty():
		return
	var started := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8086
	_streams["disc_fire"] = _wav(_disc_fire(rng))
	_streams["disc_blast"] = _wav(_disc_blast(rng))
	_streams["chaingun"] = _wav(_chaingun(rng))
	_streams["hit"] = _wav(_ticks([1900.0], 0.05))
	_streams["kill"] = _wav(_ticks([1900.0, 2500.0], 0.05))
	_streams["jet"] = _wav(_loop(_jet(rng)), true)
	_streams["ski"] = _wav(_loop(_ski(rng)), true)
	_streams["step"] = _wav(_thud(rng, 0.07, 900.0, 0.35))
	_streams["land"] = _wav(_thud(rng, 0.2, 500.0, 0.7))
	# Jingles: square and triangle notes, up for good news, down for bad.
	_streams["flag_grab"] = _wav(_jingle([523.3, 659.3, 784.0, 1046.5], 0.075))
	_streams["flag_alarm"] = _wav(_jingle([880.0, 659.3, 880.0, 659.3], 0.09))
	_streams["flag_dropped"] = _wav(_jingle([659.3, 493.9], 0.11))
	_streams["flag_returned"] = _wav(_jingle([392.0, 523.3, 659.3], 0.08))
	_streams["flag_captured"] = _wav(_jingle([523.3, 659.3, 784.0, 659.3, 784.0, 1046.5], 0.085))
	_streams["flag_lost"] = _wav(_jingle([523.3, 466.2, 392.0, 311.1], 0.12))
	_streams["click"] = _wav(_ticks([1200.0], 0.03, 0.35))
	_streams["back"] = _wav(_ticks([700.0], 0.04, 0.35))
	for team in 2:
		var bank := _syllables(rng, team)
		for line in BotLines.TEXT.size():
			_voices[line * 2 + team] = _say(bank, line, team)
	# Made after the voices, so the voices' noise stays the same.
	_streams["grenade_fire"] = _wav(_tube(rng, 0.22, 180.0, 0.8))
	_streams["grenade_blast"] = _wav(_blast(rng, 0.7, 1.4, 0.85))
	_streams["mortar_fire"] = _wav(_tube(rng, 0.5, 90.0, 0.95))
	_streams["mortar_blast"] = _wav(_blast(rng, 1.6, 0.6, 1.0))
	_streams["plasma_fire"] = _wav(_zap(rng, 0.25, 900.0, 220.0, 0.15))
	_streams["plasma_hit"] = _wav(_fizz(rng, 0.3, 0.7))
	_streams["sniper_fire"] = _wav(_zap(rng, 0.45, 3200.0, 140.0, 0.4))
	_streams["blaster_fire"] = _wav(_zap(rng, 0.12, 1800.0, 600.0, 0.05))
	_streams["blaster_hit"] = _wav(_fizz(rng, 0.1, 0.5))
	_streams["throw"] = _wav(_thud(rng, 0.14, 2400.0, 0.35))
	_streams["hand_grenade_blast"] = _wav(_blast(rng, 0.9, 1.15, 0.9))
	_streams["mine_place"] = _wav(_ticks([420.0, 840.0], 0.04, 0.5))
	_streams["mine_arm"] = _wav(_ticks([1760.0, 2350.0], 0.05, 0.45))
	_streams["mine_blast"] = _wav(_blast(rng, 1.1, 0.85, 0.95))
	_streams["pack_on"] = _wav(_ticks([660.0, 990.0], 0.05, 0.45))
	_streams["pack_off"] = _wav(_ticks([990.0, 660.0], 0.05, 0.4))
	_streams["repair"] = _wav(_loop(_repair(rng)), true)
	_streams["shield_hit"] = _wav(_zap(rng, 0.2, 2600.0, 1500.0, 0.25))
	build_ms = (Time.get_ticks_usec() - started) / 1000.0


static func get_stream(sound_name: String) -> AudioStreamWAV:
	build()
	return _streams.get(sound_name)


## A bot's line in its team's voice.
static func voice(line: int, team: int) -> AudioStreamWAV:
	build()
	return _voices.get(line * 2 + clampi(team, 0, 1))


static func _wav(samples: PackedFloat32Array, loop := false, rate := RATE) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = _bytes(samples)
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func _bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	return bytes


static func _buffer(seconds: float, rate := RATE) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(seconds * rate))
	return buffer


## Scales so the loudest sample is at peak.
static func _normalise(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0001
	for s in samples:
		top = maxf(top, absf(s))
	var k := peak / top
	for i in samples.size():
		samples[i] *= k
	return samples


## A low thump falling in pitch with a puff of noise: the disc leaving.
static func _disc_fire(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buffer(0.32)
	var phase := 0.0
	var low := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var freq := 70.0 + 260.0 * exp(-t * 18.0)
		phase += freq / RATE
		var body := sin(phase * TAU) * exp(-t * 9.0)
		# A little square on top for the retro edge.
		body += 0.25 * signf(sin(phase * TAU * 2.0)) * exp(-t * 22.0)
		low += 0.25 * (rng.randf_range(-1.0, 1.0) - low)
		out[i] = body + low * 0.9 * exp(-t * 30.0)
	return _normalise(out, 0.9)


## A boom: low noise that darkens as it fades, over a falling sub tone.
static func _disc_blast(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buffer(1.1)
	var low := 0.0
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var cut := 0.04 + 0.5 * exp(-t * 7.0)
		low += cut * (rng.randf_range(-1.0, 1.0) - low)
		phase += (32.0 + 50.0 * exp(-t * 6.0)) / RATE
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0)
		out[i] = low * 2.2 * exp(-t * 3.2) + sin(phase * TAU) * 0.8 * exp(-t * 4.0) + crack * 0.5
	for i in out.size():
		out[i] = tanh(out[i] * 1.5)
	return _normalise(out, 0.95)


## A short sharp crack with a buzz under it.
static func _chaingun(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buffer(0.08)
	var phase := 0.0
	var band := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += (190.0 - 600.0 * t) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		band += 0.5 * (noise - band)
		out[i] = (band * 0.8 + signf(sin(phase * TAU)) * 0.35) * exp(-t * 55.0)
	return _normalise(out, 0.8)


## A hollow pop out of a tube with a puff of air, for the grenade launcher
## and mortar. freq is the pop's pitch.
static func _tube(rng: RandomNumberGenerator, length: float, freq: float, peak: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var phase := 0.0
	var low := 0.0
	for i in out.size():
		var t := float(i) / RATE
		phase += freq * (1.0 + 1.5 * exp(-t * 40.0)) / RATE
		var pop := sin(phase * TAU) * exp(-t * 6.0 / length)
		low += 0.15 * (rng.randf_range(-1.0, 1.0) - low)
		out[i] = pop + low * 1.6 * exp(-t * 14.0 / length)
	return _normalise(out, peak)


## A boom like the disc's, length seconds long; brightness above 1 is
## sharper and smaller, below 1 deeper and bigger.
static func _blast(rng: RandomNumberGenerator, length: float, brightness: float, peak: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var low := 0.0
	var phase := 0.0
	var fade := 3.5 / length
	for i in out.size():
		var t := float(i) / RATE
		var cut := (0.03 + 0.5 * exp(-t * 7.0)) * brightness
		low += minf(cut, 0.9) * (rng.randf_range(-1.0, 1.0) - low)
		phase += (24.0 + 50.0 * exp(-t * 5.0)) * brightness / RATE
		var crack := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0)
		out[i] = tanh((low * 2.2 * exp(-t * fade) + sin(phase * TAU) * 0.9 * exp(-t * fade * 1.2) + crack * 0.5) * 1.6)
	return _normalise(out, peak)


## A falling zap: a square wave sweeping from high to low with a little
## noise, for the energy weapons. buzz is how much noise.
static func _zap(rng: RandomNumberGenerator, length: float, high: float, low: float, buzz: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var phase := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var share := t / length
		phase += lerpf(high, low, sqrt(share)) / RATE
		var wave := signf(sin(phase * TAU)) * 0.5 + sin(phase * TAU * 0.5) * 0.5
		out[i] = (wave + rng.randf_range(-1.0, 1.0) * buzz) * pow(1.0 - share, 2.0) * minf(1.0, t * 800.0)
	return _normalise(out, 0.7)


## A sizzle of bright noise that fades, for plasma and blaster hits.
static func _fizz(rng: RandomNumberGenerator, length: float, peak: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var last := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		out[i] = (noise - last * 0.7) * exp(-t * 5.0 / length) * (0.7 + 0.3 * sin(t * TAU * 90.0))
		last = noise
	return _normalise(out, peak)


## Short pure ticks one after another, for hit markers and clicks.
static func _ticks(freqs: Array, length: float, peak := 0.6) -> PackedFloat32Array:
	var out := _buffer(length * freqs.size())
	var n := int(length * RATE)
	for k in freqs.size():
		var freq: float = freqs[k]
		for i in n:
			var t := float(i) / RATE
			out[k * n + i] = (sin(t * freq * TAU) + 0.3 * sin(t * freq * 2.0 * TAU)) * exp(-t * 70.0)
	return _normalise(out, peak)


## Rushing noise with a low rumble, for the jetpack.
static func _jet(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buffer(1.1)
	var low := 0.0
	var lower := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += 0.35 * (noise - low)
		lower += 0.03 * (noise - lower)
		out[i] = low * (0.7 + 0.15 * sin(t * TAU * 11.0)) + lower * 3.0
	return _normalise(out, 0.7)


## A thin hiss that swells a little, for skis on the ground.
static func _ski(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buffer(1.1)
	var low := 0.0
	var last := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += 0.6 * (noise - low)
		# High pass: what's left of the noise above the low pass.
		var high := low - last
		last = low * 0.92
		out[i] = high * (0.8 + 0.2 * sin(t * TAU * 3.0))
	return _normalise(out, 0.5)


## A soft warbling hum with a quiet crackle, for the repair pack.
static func _repair(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := _buffer(1.1)
	var low := 0.0
	for i in out.size():
		var t := float(i) / RATE
		low += 0.2 * (rng.randf_range(-1.0, 1.0) - low)
		var wobble := 0.75 + 0.25 * sin(t * TAU * 9.0)
		out[i] = (sin(t * TAU * 330.0) + 0.5 * sin(t * TAU * 495.0)) * wobble + low * 0.6
	return _normalise(out, 0.45)


## Crossfades the last 0.1 s into the start, so the loop has no click.
static func _loop(samples: PackedFloat32Array) -> PackedFloat32Array:
	var fade := int(0.1 * RATE)
	var n := samples.size() - fade
	var out := samples.slice(0, n)
	for i in fade:
		var k := float(i) / fade
		out[i] = samples[i] * k + samples[n + i] * (1.0 - k)
	return out


## A dull knock for footsteps and landing.
static func _thud(rng: RandomNumberGenerator, length: float, freq: float, peak: float) -> PackedFloat32Array:
	var out := _buffer(length)
	var low := 0.0
	var a := 1.0 - exp(-TAU * freq / RATE)
	for i in out.size():
		var t := float(i) / RATE
		low += a * (rng.randf_range(-1.0, 1.0) - low)
		out[i] = (low * 3.0 + sin(t * TAU * 70.0) * 0.4) * exp(-t * 6.0 / length)
	return _normalise(out, peak)


## Notes in a row, square with a triangle an octave down.
static func _jingle(notes: Array, length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var out := _buffer(length * notes.size() + 0.15)
	for k in notes.size():
		var freq: float = notes[k]
		var tail := n + int(0.15 * RATE) if k == notes.size() - 1 else n
		for i in tail:
			var t := float(i) / RATE
			var p := fmod(t * freq, 1.0)
			var square := 1.0 if p < 0.25 else -1.0
			var q := fmod(t * freq * 0.5, 1.0)
			var triangle := 4.0 * absf(q - 0.5) - 1.0
			out[k * n + i] += (square * 0.3 + triangle * 0.6) * minf(1.0, t * 400.0) * exp(-t * 9.0)
	return _normalise(out, 0.55)


## The robot voice's syllables for a team: a buzz through two formant filters
## and a slow ring modulator, some starting with a hiss. Half are at the
## speaking pitch and the rest a little lower, for the end of a line.
static func _syllables(rng: RandomNumberGenerator, team: int) -> Array[PackedByteArray]:
	var bank: Array[PackedByteArray] = []
	for k in SYLLABLES:
		var vowel := VOWELS[k % VOWELS.size()]
		var pitch := VOICE_PITCH[team] * (1.0 if k < SYLLABLES / 2 else 0.84) * (1.0 + 0.06 * ((k * 7) % 3 - 1))
		var length := 0.075 + 0.03 * ((k * 5) % 3)
		var hiss := k % 3 == 1
		var out := _buffer(length + (0.03 if hiss else 0.0), VOICE_RATE)
		var f1 := _band(vowel.x, 6.0)
		var f2 := _band(vowel.y, 9.0)
		var f3 := _band(2600.0 if team == 0 else 3100.0, 5.0)
		# Each filter's last two inputs and outputs.
		var s1 := Vector4.ZERO
		var s2 := Vector4.ZERO
		var s3 := Vector4.ZERO
		var ring_rate := TAU * (38.0 if team == 0 else 55.0) / VOICE_RATE
		var phase := 0.0
		var start := int(0.03 * VOICE_RATE) if hiss else 0
		for i in out.size():
			var t := float(i - start) / VOICE_RATE
			var x := 0.0
			if i < start:
				x = rng.randf_range(-1.0, 1.0) * 0.25 * sin(PI * i / start)
			else:
				phase += pitch * (1.0 - 0.15 * t / length) / VOICE_RATE
				var p := fmod(phase, 1.0)
				# Team 0 a sawtooth, team 1 a narrow pulse.
				x = (2.0 * p - 1.0) if team == 0 else (1.0 if p < 0.2 else -0.25)
				x *= minf(1.0, t * 120.0) * minf(1.0, (length - t) * 60.0)
			var y1 := f1[0] * x + f1[2] * s1.y - f1[3] * s1.z - f1[4] * s1.w
			s1 = Vector4(x, s1.x, y1, s1.z)
			var y2 := f2[0] * x + f2[2] * s2.y - f2[3] * s2.z - f2[4] * s2.w
			s2 = Vector4(x, s2.x, y2, s2.z)
			var y3 := f3[0] * x + f3[2] * s3.y - f3[3] * s3.z - f3[4] * s3.w
			s3 = Vector4(x, s3.x, y3, s3.z)
			out[i] = (y1 + y2 + y3 * 0.4) * (0.6 + 0.4 * sin(ring_rate * i))
		bank.append(_bytes(_normalise(out, 0.6)))
	return bank


## Biquad band pass coefficients [b0, b1, b2, a1, a2], divided by a0.
static func _band(freq: float, q: float) -> PackedFloat32Array:
	var w := TAU * freq / VOICE_RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	return PackedFloat32Array([alpha / a0, 0.0, -alpha / a0, -2.0 * cos(w) / a0, (1.0 - alpha) / a0])


## A line made of syllables picked by its id: one for every six letters or
## so, a radio click before it, the last one lower.
static func _say(bank: Array[PackedByteArray], line: int, team: int) -> AudioStreamWAV:
	var words := BotLines.TEXT[line]
	var count := clampi(roundi(words.length() / 6.0), 2, 6)
	var gap := PackedByteArray()
	gap.resize(int(0.025 * VOICE_RATE) * 2)
	var click := _buffer(0.02, VOICE_RATE)
	for i in click.size():
		click[i] = (0.3 if (i / 8) % 2 == 0 else -0.3) * (1.0 - float(i) / click.size())
	var data := _bytes(click)
	data.append_array(gap)
	var half := SYLLABLES / 2
	for k in count:
		var pick := (line * 7 + k * 5 + team * 3) % half
		if k == count - 1:
			pick += half
		data.append_array(bank[pick])
		if (line + k) % 2 == 0:
			data.append_array(gap)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = VOICE_RATE
	stream.data = data
	return stream
