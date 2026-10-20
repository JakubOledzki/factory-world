shader_type canvas_item;
// Outlines and brightens a sprite while the mouse is over it.

uniform bool enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 0.78, 0.35, 1.0);
uniform float width = 2.0;

// In fragment() COLOR already holds the texture's colour, so keep the node's modulate apart.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled) {
		vec2 px = TEXTURE_PIXEL_SIZE * width;
		float around = 0.0;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			around = max(around, texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px).a);
		}
		float edge = clamp(around - c.a, 0.0, 1.0);
		c = vec4(mix(c.rgb * 1.3, outline_color.rgb, edge), max(c.a, edge * outline_color.a));
	}
	COLOR = c * modulate;
}
