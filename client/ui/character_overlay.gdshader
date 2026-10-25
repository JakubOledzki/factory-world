shader_type canvas_item;
// A garment drawn over the character: rendered in its own colours, only lit like the place.

uniform vec3 light = vec3(1.0);

varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 shade = texture(TEXTURE, UV);
	COLOR = vec4(shade.rgb * light, shade.a) * modulate;
}
