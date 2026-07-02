shader_type sky;

// Vertical gradient (matches the dusk look: dark overhead, warm at the horizon)
uniform vec3 top_color : source_color = vec3(0.0, 0.0, 0.0);
uniform vec3 horizon_color : source_color = vec3(0.657, 0.235, 0.0);
uniform vec3 ground_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float gradient_curve : hint_range(0.1, 4.0) = 0.6;

// Star field
uniform float star_scale : hint_range(20.0, 400.0) = 120.0;    // more = smaller, denser cells
uniform float star_coverage : hint_range(0.0, 0.2) = 0.04;     // fraction of cells that hold a star
uniform float star_size : hint_range(0.01, 0.5) = 0.15;        // dot radius within a cell
uniform float star_brightness : hint_range(0.0, 4.0) = 1.5;
uniform float twinkle_speed : hint_range(0.0, 10.0) = 3.0;
uniform float twinkle_strength : hint_range(0.0, 1.0) = 0.6;
uniform float horizon_fade : hint_range(0.0, 0.5) = 0.08;      // hide stars right at the horizon

// Shooting star
uniform vec3 meteor_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float meteor_period : hint_range(1.0, 30.0) = 7.0;     // seconds between attempts
uniform float meteor_chance : hint_range(0.0, 1.0) = 0.7;      // fraction of periods that fire one
uniform float meteor_duration : hint_range(0.2, 4.0) = 1.1;    // seconds the streak is visible
uniform float meteor_length : hint_range(0.05, 1.0) = 0.35;    // tail length
uniform float meteor_thickness : hint_range(0.002, 0.1) = 0.02;
uniform float meteor_brightness : hint_range(0.0, 4.0) = 2.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float star_field(vec3 dir) {
	vec3 sp = dir * star_scale;
	vec3 cell = floor(sp);

	// Only some cells contain a star
	if (hash13(cell) > star_coverage) {
		return 0.0;
	}

	// Random position inside the cell so stars aren't grid-aligned
	vec3 rnd = hash33(cell + 11.0);
	vec3 star_pos = cell + 0.5 + (rnd - 0.5) * 0.8;
	float d = length(sp - star_pos);
	float dot_val = smoothstep(star_size, 0.0, d);

	// Per-star twinkle and brightness variation
	float seed = hash13(cell + 3.0);
	float tw = 0.5 + 0.5 * sin(TIME * twinkle_speed + seed * 60.0);
	dot_val *= mix(1.0, tw, twinkle_strength);
	float mag = mix(0.3, 1.0, hash13(cell + 7.0));

	return dot_val * mag;
}

float meteor(vec3 dir) {
	// Each period is one "attempt" at a shooting star; a random subset fire.
	float idx = floor(TIME / meteor_period);
	float local = fract(TIME / meteor_period) * meteor_period;

	if (hash13(vec3(idx, 1.0, 2.0)) > meteor_chance) {
		return 0.0;
	}

	// Random start offset within the period, and normalized flight progress 0..1
	float start = hash13(vec3(idx, 3.0, 4.0)) * (meteor_period - meteor_duration);
	float t = (local - start) / meteor_duration;
	if (t < 0.0 || t > 1.0) {
		return 0.0;
	}

	// Random start point in the upper sky and a generally-downward travel direction
	vec3 ra = hash33(vec3(idx, 5.0, 6.0));
	vec3 start_dir = normalize(vec3(ra.x * 2.0 - 1.0, mix(0.35, 1.0, ra.y), ra.z * 2.0 - 1.0));
	vec3 rb = hash33(vec3(idx, 7.0, 8.0));
	vec3 travel = normalize(vec3(rb.x * 2.0 - 1.0, -abs(rb.y) * 0.5 - 0.1, rb.z * 2.0 - 1.0));
	float arc = mix(0.4, 0.9, hash13(vec3(idx, 9.0, 10.0)));

	// Head sweeps along the arc; tail trails behind it
	vec3 head = normalize(start_dir + travel * arc * t);
	vec3 rel = dir - head;
	float along = dot(rel, travel);
	float perp = length(rel - travel * along);

	float head_glow = smoothstep(meteor_thickness, 0.0, length(rel));
	float tfac = clamp(-along / meteor_length, 0.0, 1.0);
	float tail = smoothstep(meteor_thickness, 0.0, perp) * step(along, 0.0) * (1.0 - tfac);

	float life = sin(t * 3.14159265);  // fade in and out across the flight
	return (head_glow + tail) * life * meteor_brightness;
}

void sky() {
	float up = EYEDIR.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), gradient_curve));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 4.0, 0.0, 1.0));
	}

	float mask = smoothstep(0.0, horizon_fade, up);
	float s = star_field(EYEDIR) * mask * star_brightness;
	col += vec3(s);

	col += meteor_color * meteor(EYEDIR) * mask;

	COLOR = col;
}
