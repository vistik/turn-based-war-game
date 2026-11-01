class_name MusicComposer
extends RefCounted
## Original music, synthesised in code like the rest of the game's art: a looping theme per theatre and mood.
##
## Moods: "menu" (slow, setting the scene) and "battle" (driving). Each theatre has its own sound:
## - normandy: D minor march. Low strings, a horn melody, snare drum and timpani.
## - vietnam: E minor. Tremolo electric guitar through a spring-like reverb, toms, shaker, bass.
## - modern: D Hijaz (Phrygian dominant). A drone, a plucked oud-like lute, frame drum and darbuka.
## Every theme is composed from its recipe with a fixed seed, so it always sounds the same, and rendered as a
## seamless loop (notes ringing past the end wrap round to the start).

const RATE := 22050
const MOODS := ["menu", "battle"]
const TABLE_SIZE := 2048


## The theme as a looping 16-bit mono stream.
static func render(theatre_id: String, mood: String) -> AudioStreamWAV:
	var song := Song.new(theatre_id, mood)
	song.compose()
	return song.to_stream()


## One theme being composed and rendered.
class Song:
	extends RefCounted
	const RATE := 22050
	const TABLE_SIZE := 2048
	var theatre := ""
	var mood := ""
	var bpm := 90.0
	var bars := 16
	var beat := 0.0
	var buf := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	var _tables := {}
	var _noise := PackedFloat32Array()

	func _init(p_theatre: String, p_mood: String) -> void:
		theatre = p_theatre
		mood = p_mood
		rng.seed = hash(theatre + "/" + mood)
		_noise.resize(65536)
		for i in _noise.size():
			_noise[i] = rng.randf_range(-1.0, 1.0)

	func compose() -> void:
		match theatre:
			"vietnam":
				_vietnam()
			"modern":
				_modern()
			_:
				_normandy()
		_reverb(0.3 if mood == "menu" else 0.2)

	func _start(p_bpm: float, p_bars: int) -> void:
		bpm = p_bpm
		bars = p_bars
		beat = 60.0 / bpm
		buf.resize(int(bars * 4 * beat * RATE))
		buf.fill(0.0)

	# --- Normandy: a march in D minor ---

	func _normandy() -> void:
		var battle := mood == "battle"
		_start(100.0 if battle else 72.0, 16)
		var scale := [62, 64, 65, 67, 69, 70, 72]  # D natural minor from D4
		# Dm Bb F C | Dm Bb F C | Gm Dm A Dm | Gm Bb A Dm  (scale degrees of the chord roots, A as V)
		var roots := [0, 5, 2, 6, 0, 5, 2, 6, 3, 0, 4, 0, 3, 5, 4, 0]
		for bar in bars:
			var chord := _triad(scale, roots[bar], -12, bar % 4 == 2 and roots[bar] == 4)
			var t := bar * 4.0
			# Low strings: the chord held through the bar (battle: a pulsing eighth-note ostinato on the root).
			if battle:
				for e in 8:
					note(t + e * 0.5, 0.45, chord[0] - 12, "strings", 0.32 if e % 2 == 0 else 0.22)
				for n in chord:
					note(t, 3.9, n, "strings", 0.12)
			else:
				for n in chord:
					note(t, 4.0, n, "strings", 0.16)
				note(t, 4.0, chord[0] - 12, "strings", 0.14)
			# Timpani on the downbeat (and beat 3 in battle).
			note(t, 1.5, chord[0] - 24, "timpani", 0.5)
			if battle:
				note(t + 2.0, 1.0, chord[0] - 24, "timpani", 0.35)
			# Snare: a march pattern, with a roll into each phrase.
			_snare_bar(t, battle, bar % 4 == 3)
		# The horn melody: a motif, answered, then a falling cadence; brass stabs in battle.
		var motif := _motif(scale, 8.0, battle)
		_play_phrases(motif, scale, "horn", 0.34, 12 if battle else 0, [0, 0, 3, 0])
		if battle:
			for bar in bars:
				if bar % 2 == 1:
					var chord := _triad(scale, roots[bar], 0, false)
					for n in chord:
						note(bar * 4.0 + 1.5, 0.35, n, "horn", 0.16)

	func _snare_bar(t: float, battle: bool, roll: bool) -> void:
		if roll:
			for s in (16 if battle else 8):
				note(t + 2.0 + s * (2.0 / (16 if battle else 8)), 0.2, 0, "snare", 0.12 + 0.02 * s)
			for b in 2:
				note(t + b, 0.3, 0, "snare", 0.35)
			return
		var hits := [0.0, 1.0, 1.75, 2.0, 3.0] if not battle else [0.0, 0.5, 1.0, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 3.75]
		for h: float in hits:
			var accent := fmod(h, 1.0) == 0.0
			note(t + h, 0.3, 0, "snare", (0.4 if accent else 0.22) * (0.6 if not battle else 1.0))

	# --- Vietnam: tremolo guitar in E minor ---

	func _vietnam() -> void:
		var battle := mood == "battle"
		_start(112.0 if battle else 68.0, 16)
		var scale := [64, 67, 69, 71, 74, 76, 79]  # E minor pentatonic from E4 (E G A B D)
		var dorian := [64, 66, 67, 69, 71, 73, 74]
		# Em D C Am, twice, then Em G D Em.
		var progression := [[52, 55, 59], [50, 54, 57], [48, 52, 55], [45, 48, 52]]
		var ending := [[52, 55, 59], [55, 59, 62], [50, 54, 57], [52, 55, 59]]
		for bar in bars:
			var chord: Array = (progression if bar < 12 else ending)[bar % 4]
			var t := bar * 4.0
			# Organ-ish pad, low.
			for n: int in chord:
				note(t, 4.0, n, "pad", 0.1 if battle else 0.13)
			# The guitar: arpeggios through the chord, tremolo picking.
			var pattern := [0, 1, 2, 1, 0, 2, 1, 2] if not battle else [0, 2, 1, 2, 0, 2, 1, 0]
			for e in 8:
				note(t + e * 0.5, 0.5, chord[pattern[e]] + 12, "tremolo", 0.2 if battle else 0.17)
			if battle:
				# Driving bass, toms, a shaker and a backbeat.
				for e in 8:
					note(t + e * 0.5, 0.4, chord[0] - 12, "bass", 0.36 if e % 2 == 0 else 0.26)
				for h: float in [0.0, 0.75, 1.5, 2.0, 2.75, 3.5]:
					note(t + h, 0.6, 40 if h < 2.0 else 43, "tom", 0.45)
				for s in 16:
					note(t + s * 0.25, 0.1, 0, "shaker", 0.08 if s % 2 == 0 else 0.05)
				note(t + 1.0, 0.3, 0, "snare", 0.32)
				note(t + 3.0, 0.3, 0, "snare", 0.32)
			else:
				# Distant toms and insects.
				if bar % 2 == 0:
					note(t + 3.0, 1.2, 38, "tom", 0.22)
				for s in 8:
					if rng.randf() < 0.5:
						note(t + s * 0.5 + rng.randf() * 0.2, 0.08, 0, "shaker", 0.025)
		var motif := _motif(dorian if battle else scale, 8.0, battle)
		_play_phrases(motif, dorian if battle else scale, "tremolo", 0.24, 0, [0, 1, 0, -1])

	# --- Afghanistan and Iraq: a drone in D Hijaz ---

	func _modern() -> void:
		var battle := mood == "battle"
		_start(96.0 if battle else 64.0, 16)
		var hijaz := [62, 63, 66, 67, 69, 70, 72]  # D Eb F# G A Bb C
		for bar in bars:
			var t := bar * 4.0
			# The drone on D and A, swelling every two bars.
			if bar % 2 == 0:
				note(t, 8.0, 38, "drone", 0.22)
				note(t, 8.0, 45, "drone", 0.12)
			if battle:
				# Darbuka in maqsum: doum tek - tek doum - tek -, and a low synth pulse.
				for hit: Array in [[0.0, "doum"], [0.5, "tek"], [1.5, "tek"], [2.0, "doum"], [3.0, "tek"], [3.5, "tek"], [3.75, "tek"]]:
					note(t + hit[0], 0.4, 0, hit[1], 0.45 if hit[1] == "doum" else 0.25)
				for e in 8:
					note(t + e * 0.5, 0.35, 38 if e % 4 != 3 else 39, "bass", 0.3)
				# A plucked ostinato.
				var riff := [0, 1, 2, 1, 3, 2, 1, 0]
				for e in 8:
					note(t + e * 0.5, 0.6, hijaz[riff[e]] - 12, "pluck", 0.22)
			else:
				# A frame drum, slow and soft.
				note(t, 1.0, 0, "doum", 0.3)
				note(t + 2.5, 0.4, 0, "tek", 0.12)
		# The lute improvises (taqsim) over the drone: phrases built on the scale, resolving to D.
		var t := 0.0
		var degree := 0
		while t < bars * 4.0 - 2.0:
			var phrase := rng.randi_range(4, 8)
			for i in phrase:
				var step: int = [-1, 1, 1, -2, 2, 0, -1][rng.randi_range(0, 6)]
				degree = clampi(degree + step, -3, 9)
				var dur: float = [0.5, 0.5, 0.25, 1.0, 0.75][rng.randi_range(0, 4)]
				if battle:
					dur = [0.5, 0.25, 0.25, 0.5][rng.randi_range(0, 3)]
				var pitch := _degree(hijaz, degree)
				note(t, dur + 0.4, pitch, "pluck", 0.32)
				if dur >= 0.75 and not battle:
					# A tremolo flourish on long notes, as on an oud.
					for k in 3:
						note(t + 0.125 * (k + 1), 0.2, pitch, "pluck", 0.12)
				t += dur
			note(t, 1.5, _degree(hijaz, 0 if rng.randf() < 0.6 else 4), "pluck", 0.3)
			degree = 0
			t += 2.0 if not battle else 1.0

	# --- Composition helpers ---

	## The scale's degree (wrapping into higher or lower octaves) as a MIDI note.
	func _degree(scale: Array, degree: int) -> int:
		var octave := floori(degree / float(scale.size()))
		return scale[posmod(degree, scale.size())] + 12 * octave

	## The triad on a scale degree, shifted by `shift` semitones; `major` raises the third (the dominant).
	func _triad(scale: Array, degree: int, shift: int, major: bool) -> Array:
		var notes := [_degree(scale, degree), _degree(scale, degree + 2), _degree(scale, degree + 4)]
		if major:
			notes[1] += 1
		return notes.map(func(n: int) -> int: return n + shift)

	## A two-bar melodic motif: [beat offset, length in beats, scale degree], a random walk that ends on a
	## chord tone.
	func _motif(scale: Array, length: float, busy: bool) -> Array:
		var rhythms := [[1.0, 0.5, 0.5, 1.0, 1.0], [1.5, 0.5, 1.0, 1.0], [0.5, 0.5, 1.0, 0.5, 0.5, 1.0], [2.0, 1.0, 1.0]]
		if busy:
			rhythms = [[0.5, 0.5, 0.5, 0.5, 1.0, 1.0], [0.75, 0.25, 0.5, 0.5, 1.0, 1.0], [0.5, 0.25, 0.25, 1.0, 0.5, 0.5, 1.0]]
		var notes := []
		var t := 0.0
		var degree := rng.randi_range(2, 4)
		while t < length - 0.01:
			var rhythm: Array = rhythms[rng.randi_range(0, rhythms.size() - 1)]
			for d: float in rhythm:
				if t >= length - 0.01:
					break
				notes.append([t, minf(d, length - t), degree])
				degree = clampi(degree + [-2, -1, -1, 1, 1, 2, 0][rng.randi_range(0, 6)], -1, 8)
				t += d
		notes[-1][2] = [0, 2, 4][rng.randi_range(0, 2)]
		return notes

	## Plays a motif through the loop: once per two bars, transposed by `shifts` (in scale degrees) per
	## repetition, an octave up by `octave` semitones, the last phrase falling to the tonic.
	func _play_phrases(motif: Array, scale: Array, instrument: String, velocity: float, octave: int, shifts: Array) -> void:
		var reps := bars / 2
		for r in reps:
			var shift: int = shifts[r % shifts.size()]
			for i in motif.size():
				var m: Array = motif[i]
				var degree: int = m[2] + shift
				if r == reps - 1 and i == motif.size() - 1:
					degree = 0
				# Every other phrase rests through its second half, so the melody breathes.
				if r % 2 == 1 and m[0] >= 4.0 and i < motif.size() - 1:
					continue
				note(r * 8.0 + m[0], m[1] * 0.95, _degree(scale, degree) + octave, instrument, velocity)

	# --- Synthesis ---

	## Adds a note: start and length in beats, a MIDI note number (ignored by drums), an instrument, a volume.
	func note(start_beats: float, length_beats: float, midi: int, instrument: String, velocity: float) -> void:
		var start := int(start_beats * beat * RATE)
		var length := length_beats * beat
		var freq := 440.0 * pow(2.0, (midi - 69) / 12.0)
		match instrument:
			"strings":
				_tone(start, length, freq, velocity, _table("saw", 8), 0.25, 0.4, 5.0, 0.004, 0.0, 0.12)
			"horn":
				_tone(start, length, freq, velocity, _table("horn", 7), 0.06, 0.25, 5.5, 0.006, 0.0, 0.3)
			"pad":
				_tone(start, length, freq, velocity, _table("organ", 6), 0.4, 0.6, 0.0, 0.0, 0.0, 0.2)
			"tremolo":
				_tone(start, length, freq, velocity, _table("tri", 9), 0.005, 0.15, 0.0, 0.0, 7.5, 0.5, 1.8)
			"bass":
				_tone(start, length, freq, velocity, _table("saw", 6), 0.01, 0.08, 0.0, 0.0, 0.0, 0.08)
			"drone":
				_tone(start, length, freq, velocity, _table("saw", 10), 1.2, 1.5, 0.15, 0.003, 0.0, 0.06)
			"pluck":
				_pluck(start, length, freq, velocity)
			"snare":
				_drum(start, 0.18, 190.0, velocity, 0.75, 0.0, 0.9)
			"timpani":
				_drum(start, 1.1, freq, velocity, 0.05, 0.4, 0.15)
			"tom":
				_drum(start, 0.45, freq * 0.5, velocity, 0.1, 0.5, 0.25)
			"shaker":
				_drum(start, 0.07, 0.0, velocity, 1.0, 0.0, 0.95)
			"doum":
				_drum(start, 0.5, 85.0, velocity, 0.08, 0.35, 0.2)
			"tek":
				_drum(start, 0.09, 400.0, velocity, 0.6, 0.0, 0.85)

	## One cycle of a waveform with `harmonics` partials: "saw" (all, 1/n), "tri" (odd, 1/n²), "horn" (all,
	## bright), "organ" (a few strong ones).
	func _table(shape: String, harmonics: int) -> PackedFloat32Array:
		var key := "%s%d" % [shape, harmonics]
		if _tables.has(key):
			return _tables[key]
		var table := PackedFloat32Array()
		table.resize(TABLE_SIZE)
		var peak := 0.0
		for i in TABLE_SIZE:
			var x := TAU * i / TABLE_SIZE
			var v := 0.0
			for k in range(1, harmonics + 1):
				match shape:
					"saw":
						v += sin(x * k) / k
					"tri":
						if k % 2 == 1:
							v += sin(x * k) / (k * k) * (1.0 if (k / 2) % 2 == 0 else -1.0)
					"horn":
						v += sin(x * k) / pow(k, 0.8)
					"organ":
						v += sin(x * k) * ([1.0, 0.5, 0.0, 0.3, 0.0, 0.15][k - 1] if k <= 6 else 0.0)
			table[i] = v
			peak = maxf(peak, absf(v))
		for i in table.size():
			table[i] /= maxf(peak, 0.0001)
		_tables[key] = table
		return table

	## A held tone from a wavetable: attack, release, vibrato (rate Hz, depth as a fraction of the pitch),
	## tremolo (amplitude wobble, Hz), a one-pole low-pass (0..1, lower is darker) and overdrive.
	func _tone(start: int, length: float, freq: float, velocity: float, table: PackedFloat32Array, attack: float, release: float,
			vibrato: float, depth: float, tremolo: float, brightness: float, drive := 0.0) -> void:
		var n := buf.size()
		var total := int((length + release) * RATE)
		var held := int(length * RATE)
		var attack_samples := maxi(1, int(attack * RATE))
		var release_samples := maxi(1, int(release * RATE))
		var phase := 0.0
		var step := freq * TABLE_SIZE / RATE
		var lp := 0.0
		var a := clampf(brightness, 0.01, 1.0)
		for s in total:
			var env := 1.0
			if s < attack_samples:
				env = float(s) / attack_samples
			if s > held:
				env *= 1.0 - float(s - held) / release_samples
			if env <= 0.0:
				break
			var t := float(s) / RATE
			var wobble := 1.0 + depth * sin(TAU * vibrato * t) if vibrato > 0.0 else 1.0
			phase = fmod(phase + step * wobble, TABLE_SIZE)
			var v := table[int(phase)]
			if tremolo > 0.0:
				v *= 0.55 + 0.45 * sin(TAU * tremolo * t)
			if drive > 0.0:
				v = tanh(v * drive) / tanh(drive)
			lp += a * (v - lp)
			buf[(start + s) % n] += lp * env * velocity

	## A plucked string (Karplus-Strong): a burst of noise in a delay line the length of one period, averaged
	## each pass so it rings and darkens like a lute or guitar string.
	func _pluck(start: int, length: float, freq: float, velocity: float) -> void:
		var n := buf.size()
		var period := maxi(2, int(RATE / freq))
		var line := PackedFloat32Array()
		line.resize(period)
		for i in period:
			line[i] = _noise[(start + i * 7) % _noise.size()]
		var total := int((length + 0.6) * RATE)
		var damp := 0.996
		for s in total:
			var i := s % period
			var j := (s + 1) % period
			var v := line[i]
			line[i] = (line[i] + line[j]) * 0.5 * damp
			var fade := 1.0 if s < length * RATE else maxf(0.0, 1.0 - (s - length * RATE) / (0.6 * RATE))
			buf[(start + s) % n] += v * velocity * fade

	## A drum: a decaying mix of noise (`noise` 0..1) and a tone at `freq` that drops in pitch by `sweep`;
	## `bright` is the noise's brightness.
	func _drum(start: int, decay: float, freq: float, velocity: float, noise: float, sweep: float, bright: float) -> void:
		var n := buf.size()
		var total := int(decay * 3.0 * RATE)
		var phase := 0.0
		var lp := 0.0
		var offset := int(_noise.size() * fmod(start * 0.618, 1.0))
		for s in total:
			var t := float(s) / RATE
			var env := exp(-t / decay * 2.0)
			var f := freq * (1.0 - sweep * minf(1.0, t / decay))
			phase += TAU * f / RATE
			var white := _noise[(offset + s) % _noise.size()]
			lp += bright * (white - lp)
			var v := sin(phase) * (1.0 - noise) + lp * noise
			buf[(start + s) % n] += v * env * velocity

	## A light room reverb (three feedback delays, run round the loop twice so the tail wraps seamlessly),
	## mixed in at `wet`.
	func _reverb(wet: float) -> void:
		var n := buf.size()
		var dry := buf.duplicate()
		var mixed := PackedFloat32Array()
		mixed.resize(n)
		for delay_s: float in [0.0297, 0.0371, 0.0411, 0.0437]:
			var d := int(delay_s * RATE * 3.0)
			var line := PackedFloat32Array()
			line.resize(n)
			for pass_ in 2:
				for i in n:
					line[i] = dry[i] + 0.72 * line[(i - d + n) % n]
			for i in n:
				mixed[i] += line[i] * 0.25
		for i in n:
			buf[i] = dry[i] * (1.0 - wet) + mixed[i] * wet

	## The theme as a looping 16-bit stream, normalised.
	func to_stream() -> AudioStreamWAV:
		var peak := 0.0001
		for v in buf:
			peak = maxf(peak, absf(v))
		var gain := 0.85 / peak
		var data := PackedByteArray()
		data.resize(buf.size() * 2)
		for i in buf.size():
			data.encode_s16(i * 2, int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0))
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = RATE
		stream.stereo = false
		stream.data = data
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
		return stream
