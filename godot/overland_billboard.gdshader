// The overland billboard (QudWorld._build_props): a Qud tile standing up, facing the camera
// about its own vertical (Godot's BILLBOARD_FIXED_Y, written out so the fragment can do
// what StandardMaterial3D cannot), tinted by the MultiMesh instance colour the light bake
// sets, and DARKER THE FURTHER AWAY it stands: full colour up to dark_near metres, down to
// dark_min at dark_far and beyond, so the marsh recedes instead of standing as one bright
// wall of sprites.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest;
uniform float dark_near = 30.0;    // metres (600 px at Track.U)
uniform float dark_far = 150.0;
uniform float dark_min = 0.35;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	float d = length(VERTEX);
	float k = mix(1.0, dark_min, smoothstep(dark_near, dark_far, d));
	ALBEDO = c.rgb * COLOR.rgb * k;
}
