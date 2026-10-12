shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D texture_roughness : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

uniform float viewmodel_fov : hint_range(10.0, 120.0) = 70.0;

void vertex() {
	if (viewmodel_fov > 0.0) {
		float onetanfov = 1.0 / tan(0.5 * (viewmodel_fov * PI / 180.0));
		float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
		PROJECTION_MATRIX[1][1] = -onetanfov;
		PROJECTION_MATRIX[0][0] = onetanfov / aspect;
	}
	
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX.xyz, 1.0);
	// Godot 4.3+ Reverse-Z clip space: mix Z towards W to bring it near the camera
	POSITION.z = mix(POSITION.z, POSITION.w, 0.9);
}

void fragment() {
	vec4 tex_color = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * tex_color.rgb;
	METALLIC = metallic * texture(texture_metallic, UV).r;
	ROUGHNESS = roughness * texture(texture_roughness, UV).g;
	SPECULAR = specular;
}
