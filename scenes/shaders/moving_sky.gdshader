shader_type sky;

uniform sampler2D sky_texture : filter_linear, source_color;

void sky() {
	// Use TIME to shift the horizontal coordinate
	vec2 uv = SKY_COORDS + vec2(TIME * 0.01, 0.0);
	COLOR = texture(sky_texture, uv).rgb;
}
