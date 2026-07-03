extends AudioStreamPlayer

@export var car_path: NodePath = NodePath("..")
@export var mix_rate: float = 11025.0

@export_group("Engine")
@export var idle_hz: float = 45.0
@export var redline_hz: float = 240.0
@export var gears: int = 5
@export var idle_volume: float = 0.25
@export var throttle_volume: float = 1.0
@export var rpm_smooth: float = 5.0          # how fast the pitch chases the target
@export var volume_smooth: float = 6.0

@export_group("Crunch")
@export var bit_depth: int = 2               # fewer bits = crunchier quantization
@export var duty: float = 0.5                # pulse-wave duty cycle
@export var detune: float = 1.01             # 2nd oscillator detune for thickness
@export var noise_amount: float = 0.06
@export var master_gain: float = 0.5

var car: Node
var playback: AudioStreamGeneratorPlayback

var phase1: float = 0.0
var phase2: float = 0.0
var phase_sub: float = 0.0
var cur_freq: float = 45.0
var cur_vol: float = 0.0

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
	_update_targets(delta)
	_fill_buffer()

func _update_targets(delta: float) -> void:
	var speed_frac := 0.0
	var throttle := 0.0
	var drifting := false
	if car != null:
		speed_frac = clampf(absf(car.current_speed) / maxf(car.max_speed, 0.01), 0.0, 1.0)
		throttle = Input.get_action_strength("forward")
		drifting = car.is_drifting

	# Rev up within each gear, then drop on the "shift" - the classic engine curve.
	var g := clampf(speed_frac * float(gears), 0.0, float(gears))
	var within_gear = g - floor(g)
	var target_freq := lerpf(idle_hz, redline_hz, 0.25 + 0.75 * within_gear)
	if drifting:
		target_freq *= 1.05

	var target_vol := lerpf(idle_volume, throttle_volume, maxf(throttle, speed_frac * 0.5))

	cur_freq = lerpf(cur_freq, target_freq, clampf(delta * rpm_smooth, 0.0, 1.0))
	cur_vol = lerpf(cur_vol, target_vol, clampf(delta * volume_smooth, 0.0, 1.0))

func _fill_buffer() -> void:
	if playback == null:
		return

	var frames := playback.get_frames_available()
	var levels := float(1 << bit_depth)
	var inv_rate := 1.0 / mix_rate

	for _i in frames:
		phase1 = fmod(phase1 + cur_freq * inv_rate, 1.0)
		phase2 = fmod(phase2 + cur_freq * detune * inv_rate, 1.0)
		phase_sub = fmod(phase_sub + cur_freq * 0.5 * inv_rate, 1.0)

		var s := 0.0
		s += (1.0 if phase1 < duty else -1.0) * 0.5           # main pulse
		s += (1.0 if phase2 < duty else -1.0) * 0.3           # detuned pulse (thickness)
		s += (1.0 if phase_sub < 0.5 else -1.0) * 0.2         # sub-octave (body)
		s += (randf() * 2.0 - 1.0) * noise_amount             # combustion grit
		s = clampf(s, -1.0, 1.0)

		# Bit-crush the waveform, then apply gain so the crunch is constant at any volume.
		s = round(s * levels) / levels
		s *= cur_vol * master_gain

		playback.push_frame(Vector2(s, s))
