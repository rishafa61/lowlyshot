extends CanvasLayer

@onready var scope_mask = $ScopeMask

func _ready():
	get_tree().root.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized() # Call once at startup

func _on_viewport_resized():
	var viewport_size = get_viewport().get_visible_rect().size
	var aspect = viewport_size.x / viewport_size.y
	scope_mask.material.set_shader_parameter("aspect_ratio", aspect)
