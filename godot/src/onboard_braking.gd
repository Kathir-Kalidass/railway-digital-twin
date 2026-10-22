class_name OnboardBraking
extends RefCounted

## Pure stopping-distance and safe-speed calculations.
## Formula: d_stop(v) = v * t_latency + v^2 / (2 * a) + d_margin


static func stopping_distance(speed_kmh: float, a: float = 2.0, t_latency: float = 0.6, d_margin: float = 25.0) -> float:
	var v_mps := maxf(0.0, speed_kmh) / 3.6
	return v_mps * t_latency + (v_mps * v_mps) / (2.0 * a) + d_margin


static func safe_speed_limit(distance_m: float, a: float = 2.0, t_latency: float = 0.6, d_margin: float = 25.0) -> float:
	if distance_m <= d_margin:
		return 0.0
	# Solve: (1 / (2*a)) * v^2 + t_latency * v + (d_margin - distance_m) = 0
	var A := 1.0 / (2.0 * a)
	var B := t_latency
	var C := d_margin - distance_m
	var disc := B * B - 4.0 * A * C
	if disc < 0.0:
		return 0.0
	var v_mps := (-B + sqrt(disc)) / (2.0 * A)
	return maxf(0.0, v_mps * 3.6)


static func should_stop(distance_m: float, speed_kmh: float, a: float = 2.0, t_latency: float = 0.6, d_margin: float = 25.0) -> bool:
	return stopping_distance(speed_kmh, a, t_latency, d_margin) >= distance_m
