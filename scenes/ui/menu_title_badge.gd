@tool
class_name MenuTitleBadge
extends Control

## Tactical 4-stripe tally badge matching modern military shooter UI reference.

@export var bar_color := Color(1.0, 0.44, 0.08):
	set(c):
		bar_color = c
		queue_redraw()

func _draw() -> void:
	var h: float = size.y
	var bar_w: float = 7.0
	var gap: float = 4.5
	var slant: float = 7.0
	
	for i in 4:
		var x: float = i * (bar_w + gap) + 2.0
		var shadow_pts := PackedVector2Array([
			Vector2(x + slant, 3.0),
			Vector2(x + bar_w + slant, 3.0),
			Vector2(x + bar_w, h + 3.0),
			Vector2(x, h + 3.0),
		])
		draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.4))
		var pts := PackedVector2Array([
			Vector2(x + slant, 0.0),
			Vector2(x + bar_w + slant, 0.0),
			Vector2(x + bar_w, h),
			Vector2(x, h),
		])
		draw_colored_polygon(pts, bar_color)
