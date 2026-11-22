class_name CharacterArt
extends RefCounted

## Procedural vector silhouettes for Circuit Bastion.
## Every shape is drawn with CanvasItem primitives so it works on desktop and
## mobile without importing textures or external art packs.

const PALETTES := {
	"scout": Color("#63d9ff"),
	"bruiser": Color("#ff8f6b"),
	"splitter": Color("#d58bff"),
	"jammer": Color("#ffca62"),
	"leech": Color("#68e3bf"),
	"phase": Color("#9ca9ff"),
	"boss": Color("#ff5f7a"),
}

static func palette(kind: String) -> Color:
	return PALETTES.get(kind, Color("#ff6b75"))

static func draw_enemy(canvas: CanvasItem, center: Vector2, size: float, kind: String, state: String, phase: float, hit_intensity := 0.0) -> void:
	var base := palette(kind)
	var bob := sin(phase * 2.0 + center.x * 0.01) * size * 0.035
	var point := center + Vector2(0.0, bob)
	var fade := 0.42 if state == "dead" else 1.0
	var body := Color(base, fade)
	match kind:
		"scout":
			_draw_scout(canvas, point, size, body, phase)
		"bruiser":
			_draw_bruiser(canvas, point, size, body, phase)
		"splitter":
			_draw_splitter(canvas, point, size, body, phase)
		"jammer":
			_draw_jammer(canvas, point, size, body, phase)
		"leech":
			_draw_leech(canvas, point, size, body, phase)
		"phase":
			_draw_phase(canvas, point, size, body, phase)
		"boss":
			_draw_boss(canvas, point, size, body, phase)
		_:
			_draw_scout(canvas, point, size, body, phase)
	if hit_intensity > 0.0 and state != "dead":
		var flash := clampf(hit_intensity, 0.0, 1.0)
		canvas.draw_circle(point, size * (0.62 + flash * 0.18), Color(1.0, 1.0, 1.0, 0.10 * flash), false, 2.0 + flash * 3.0)
		canvas.draw_line(point - Vector2(size * 0.42, size * 0.42), point + Vector2(size * 0.42, size * 0.42), Color(1.0, 0.93, 0.72, 0.72 * flash), 2.0)
		canvas.draw_line(point + Vector2(size * 0.42, -size * 0.42), point - Vector2(size * 0.42, -size * 0.42), Color(1.0, 1.0, 1.0, 0.42 * flash), 1.0)

static func draw_death_burst(canvas: CanvasItem, center: Vector2, size: float, kind: String, phase: float, intensity := 1.0) -> void:
	var base := palette(kind)
	var pulse := clampf(intensity, 0.0, 1.0)
	canvas.draw_circle(center, size * (0.34 + pulse * 0.28), Color(base, 0.08 * pulse), true)
	canvas.draw_circle(center, size * (0.34 + pulse * 0.28), Color(1.0, 0.88, 0.68, 0.60 * pulse), false, 2.0)
	for index in 8:
		var angle := float(index) * TAU / 8.0 + phase * 0.8
		var inner := center + Vector2(cos(angle), sin(angle)) * size * 0.16
		var outer := center + Vector2(cos(angle), sin(angle)) * size * (0.50 + pulse * 0.24)
		canvas.draw_line(inner, outer, Color(base, 0.75 * pulse), 2.0)
	canvas.draw_line(center - Vector2(size * 0.30, size * 0.18), center + Vector2(size * 0.30, size * 0.18), Color(1.0, 0.96, 0.80, 0.70 * pulse), 2.0)
	canvas.draw_line(center - Vector2(size * 0.18, size * 0.30), center + Vector2(size * 0.18, size * 0.30), Color(1.0, 0.96, 0.80, 0.50 * pulse), 2.0)

static func _draw_scout(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	var body := _points(center, size, [Vector2(0, -0.58), Vector2(0.48, 0), Vector2(0, 0.58), Vector2(-0.48, 0)])
	canvas.draw_colored_polygon(body, color)
	canvas.draw_colored_polygon(_points(center + Vector2(-size * 0.34, 0), size * 0.62, [Vector2(-0.62, -0.15), Vector2(-1.0, -0.45), Vector2(-0.95, 0.18), Vector2(-0.48, 0.34)]), Color(color, 0.62))
	canvas.draw_colored_polygon(_points(center + Vector2(size * 0.34, 0), size * 0.62, [Vector2(0.62, -0.15), Vector2(1.0, -0.45), Vector2(0.95, 0.18), Vector2(0.48, 0.34)]), Color(color, 0.62))
	canvas.draw_circle(center, size * 0.12, Color("#071017"))
	canvas.draw_circle(center + Vector2(size * 0.03, -size * 0.02), size * 0.055, Color("#e9fbff"))
	canvas.draw_line(center + Vector2(-size * 0.18, -size * 0.44), center + Vector2(-size * 0.38, -size * 0.72), color, 1.5)
	canvas.draw_line(center + Vector2(size * 0.18, -size * 0.44), center + Vector2(size * 0.38, -size * 0.72), color, 1.5)

static func _draw_bruiser(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	var shell := _points(center, size, [Vector2(-0.48, -0.42), Vector2(0.18, -0.58), Vector2(0.58, -0.18), Vector2(0.48, 0.44), Vector2(-0.18, 0.58), Vector2(-0.58, 0.14)])
	canvas.draw_colored_polygon(shell, color)
	canvas.draw_rect(Rect2(center + Vector2(-size * 0.75, -size * 0.30), Vector2(size * 0.30, size * 0.60)), Color(color, 0.78), true)
	canvas.draw_rect(Rect2(center + Vector2(size * 0.45, -size * 0.30), Vector2(size * 0.30, size * 0.60)), Color(color, 0.78), true)
	canvas.draw_line(center + Vector2(-size * 0.22, -size * 0.24), center + Vector2(size * 0.28, -size * 0.24), Color("#2b1820"), 2.5)
	canvas.draw_line(center + Vector2(-size * 0.22, 0), center + Vector2(size * 0.28, 0), Color("#2b1820"), 2.5)
	canvas.draw_circle(center + Vector2(0, size * 0.23), size * 0.11, Color("#ffd2a5"))
	canvas.draw_arc(center, size * 0.68, -0.8 + phase * 0.1, 2.2 + phase * 0.1, 16, Color(color, 0.46), 2.0)

static func _draw_splitter(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	var offset := sin(phase * 2.2) * size * 0.05
	canvas.draw_colored_polygon(_points(center + Vector2(-offset, 0), size, [Vector2(0, -0.62), Vector2(0.55, 0.45), Vector2(-0.55, 0.45)]), color)
	canvas.draw_colored_polygon(_points(center + Vector2(size * 0.42 + offset, size * 0.05), size * 0.48, [Vector2(0, -0.60), Vector2(0.56, 0.34), Vector2(-0.56, 0.34)]), Color(color, 0.58))
	canvas.draw_line(center + Vector2(0, -size * 0.34), center + Vector2(0, size * 0.32), Color("#2b183a"), 2.0)
	canvas.draw_circle(center + Vector2(-size * 0.16, -size * 0.08), size * 0.07, Color("#f3ddff"))
	canvas.draw_circle(center + Vector2(size * 0.16, -size * 0.08), size * 0.07, Color("#f3ddff"))

static func _draw_jammer(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	canvas.draw_rect(Rect2(center + Vector2(-size * 0.38, -size * 0.28), Vector2(size * 0.76, size * 0.58)), color, true)
	canvas.draw_rect(Rect2(center + Vector2(-size * 0.24, -size * 0.18), Vector2(size * 0.48, size * 0.36)), Color("#2b2113"), false, 2.0)
	canvas.draw_line(center + Vector2(0, -size * 0.28), center + Vector2(0, -size * 0.72), color, 2.0)
	canvas.draw_circle(center + Vector2(0, -size * 0.80), size * 0.10, Color("#fff1a3"))
	canvas.draw_arc(center + Vector2(0, -size * 0.05), size * 0.55, -2.4 + phase * 0.7, -0.7 + phase * 0.7, 12, Color(color, 0.70), 1.8)
	canvas.draw_arc(center + Vector2(0, -size * 0.05), size * 0.78, -2.3 + phase * 0.7, -0.8 + phase * 0.7, 12, Color(color, 0.34), 1.5)
	canvas.draw_circle(center + Vector2(-size * 0.18, 0), size * 0.07, Color("#071017"))
	canvas.draw_circle(center + Vector2(size * 0.18, 0), size * 0.07, Color("#071017"))

static func _draw_leech(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	var points := PackedVector2Array()
	for index in 5:
		var t := float(index) / 4.0
		points.append(center + Vector2((t - 0.5) * size * 1.15, sin(phase * 2.0 + t * 5.0) * size * 0.16))
	canvas.draw_polyline(points, Color(color, 0.82), size * 0.30, true)
	for point in points:
		canvas.draw_circle(point, size * 0.18, color)
	canvas.draw_circle(points[0], size * 0.26, Color("#2d6155"))
	canvas.draw_arc(points[0], size * 0.15, -0.8, 0.8, 8, Color("#071017"), 2.0)
	canvas.draw_line(points[4], points[4] + Vector2(size * 0.25, -size * 0.20), color, 2.0)

static func _draw_phase(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	var drift := sin(phase * 1.5) * size * 0.12
	canvas.draw_colored_polygon(_points(center + Vector2(drift, 0), size, [Vector2(-0.46, 0.48), Vector2(-0.38, -0.26), Vector2(-0.12, -0.58), Vector2(0.20, -0.44), Vector2(0.48, -0.12), Vector2(0.30, 0.52), Vector2(0, 0.30)]), color)
	canvas.draw_colored_polygon(_points(center - Vector2(size * 0.18, 0), size, [Vector2(-0.46, 0.48), Vector2(-0.38, -0.26), Vector2(-0.12, -0.58), Vector2(0.20, -0.44), Vector2(0.48, -0.12), Vector2(0.30, 0.52), Vector2(0, 0.30)]), Color(color, 0.18))
	canvas.draw_circle(center + Vector2(size * 0.13, -size * 0.10), size * 0.10, Color("#eef0ff"))
	canvas.draw_arc(center, size * 0.68, phase, phase + 4.4, 18, Color(color, 0.56), 1.6)

static func _draw_boss(canvas: CanvasItem, center: Vector2, size: float, color: Color, phase: float) -> void:
	var shell := _points(center, size, [Vector2(-0.50, -0.44), Vector2(-0.24, -0.72), Vector2(0.24, -0.72), Vector2(0.50, -0.44), Vector2(0.64, 0.10), Vector2(0.36, 0.62), Vector2(-0.36, 0.62), Vector2(-0.64, 0.10)])
	canvas.draw_colored_polygon(shell, Color(color, 0.88))
	canvas.draw_colored_polygon(_points(center, size * 0.72, [Vector2(-0.42, -0.30), Vector2(0, -0.58), Vector2(0.42, -0.30), Vector2(0.50, 0.30), Vector2(0, 0.52), Vector2(-0.50, 0.30)]), Color("#421c35"))
	canvas.draw_colored_polygon(_points(center + Vector2(-size * 0.02, -size * 0.22), size * 0.45, [Vector2(-0.12, -0.46), Vector2(0.24, -0.10), Vector2(0.12, 0.42), Vector2(-0.24, 0.10)]), Color("#ffdc76"))
	canvas.draw_circle(center + Vector2(0, -size * 0.06), size * 0.12, Color("#fff6c2"))
	canvas.draw_line(center + Vector2(-size * 0.36, -size * 0.46), center + Vector2(-size * 0.70, -size * 0.82), color, 3.0)
	canvas.draw_line(center + Vector2(size * 0.36, -size * 0.46), center + Vector2(size * 0.70, -size * 0.82), color, 3.0)
	canvas.draw_arc(center, size * 0.85, -phase * 0.8, -phase * 0.8 + 4.9, 24, Color(color, 0.72), 2.5)
	canvas.draw_arc(center, size * 1.06, phase * 0.5, phase * 0.5 + 3.8, 24, Color("#ffca62", 0.30), 1.5)

static func _points(center: Vector2, size: float, normalized: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in normalized:
		result.append(center + point * size)
	return result
