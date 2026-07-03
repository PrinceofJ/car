extends AudioStreamPlayer

# Procedural tire screech for drifting. White noise pushed through a resonant
# band-pass filter (a state-variable filter) whose center frequency wobbles via
# an LFO - that's the classic squeal. Amplitude follows the car's drift state
# and speed, then it's bit-crushed to match the crunchy retro palette.

@export var car_path: NodePath = NodePath("..")
@export var mix_rate: float = 11025.0

@export_group("Screech")
@export var freq_low: float = 900.0          # LFO sweeps center freq between these
@export var freq_high: float = 1800.0
@export var lfo_hz: float = 7.0              # squeal warble rate
@export var resonance: float = 0.6           # lower = sharper, more resonant squeal
@export var squeal_tone_amount: float = 0.35 # blend of pure tone over the filtered noise
@export var min_speed_frac: float = 0.25     # need some speed before tires screech
@export var amp_smooth: float = 10.0

@export_group("Crunch")
@export var bit_depth: int = 4
@export var master_gain: float = 0.5

var car: Node
var playback: AudioStreamGeneratorPlayback

var cur_amp: float = 0.0
var svf_low: float = 0.0
var svf_band: float = 0.0
var lfo_phase: float = 0.0
var squeal_phase: float = 0.0

func _ready() -> void:
	car = get_node_or_null(car_path)
	if car == null:
		car = get_parent()

	var gen := AudioStreamGenerator.new()
	gen.mix_rate = mix_rate
	gen.buffer_length = 0.1
	stream = gen
	play()
	playback = get_stream_playback()

func _process(delta: float) -> void:
	var target := 0.0
	if car != null and car.is_drifting:
		var sf := clampf(absf(car.current_speed) / maxf(car.max_speed, 0.01), 0.0, 1.0)
		if sf > min_speed_frac:
			target = clampf((sf - min_speed_frac) / (1.0 - min_speed_frac), 0.0, 1.0)
	cur_amp = lerpf(cur_amp, target, clampf(delta * amp_smooth, 0.0, 1.0))

	_fill_buffer()

func _fill_buffer() -> void:
	if playback == null:
		return

	var frames := playback.get_frames_available()
	var levels := float(1 << bit_depth)
	var inv_rate := 1.0 / mix_rate

	for _i in frames:
		# Wobbling band-pass center frequency
		lfo_phase = fmod(lfo_phase + lfo_hz * inv_rate, 1.0)
		var lfo := sin(lfo_phase * TAU)
		var fc := lerpf(freq_low, freq_high, 0.5 + 0.5 * lfo)

		# State-variable filter (band-pass tap) fed with white noise
		var f := 2.0 * sin(PI * fc * inv_rate)
		var noise := randf() * 2.0 - 1.0
		var high := noise - svf_low - resonance * svf_band
		svf_band += f * high
		svf_low += f * svf_band
		var bp := svf_band * 0.6

		# Tonal squeal riding an octave above the filter center
		squeal_phase = fmod(squeal_phase + fc * 2.0 * inv_rate, 1.0)
		var tone := sin(squeal_phase * TAU)

		var s := bp * (1.0 - squeal_tone_amount) + tone * squeal_tone_amount
		s *= cur_amp * master_gain

		s = round(s * levels) / levels
		s = clampf(s, -1.0, 1.0)
		playback.push_frame(Vector2(s, s))
