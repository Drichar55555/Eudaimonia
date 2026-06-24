extends ColorRect

@export_range(0.0, 1.0, 0.01) var saturation := 0.22:
	set(value):
		saturation = value
		_update_material_params()
@export_range(0.0, 1.0, 0.01) var darkness := 0.16:
	set(value):
		darkness = value
		_update_material_params()
@export_range(0.0, 1.0, 0.01) var white_preserve_threshold := 0.72:
	set(value):
		white_preserve_threshold = value
		_update_material_params()

var _shader_material: ShaderMaterial

func _ready() -> void:
	add_to_group("death_space_filters")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_setup_shader()

func set_filter_visible(value: bool) -> void:
	visible = value

func _setup_shader() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float saturation = 0.22;
uniform float darkness = 0.16;
uniform float white_preserve_threshold = 0.72;

void fragment() {
	vec4 screen = texture(screen_texture, SCREEN_UV);
	float gray = dot(screen.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(vec3(gray), screen.rgb, saturation);
	vec3 filtered = desaturated * (1.0 - darkness);
	float highlight = smoothstep(white_preserve_threshold, 1.0, max(max(screen.r, screen.g), screen.b));
	COLOR = vec4(mix(filtered, vec3(1.0), highlight), screen.a);
}
"""
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	material = _shader_material
	_update_material_params()

func _update_material_params() -> void:
	if _shader_material == null:
		return
	_shader_material.set_shader_parameter("saturation", saturation)
	_shader_material.set_shader_parameter("darkness", darkness)
	_shader_material.set_shader_parameter("white_preserve_threshold", white_preserve_threshold)
