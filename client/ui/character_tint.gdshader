shader_type canvas_item;
// Tints the grey character render: masks say which pixels are skin, shirt, pants (mask_a)
// and hair, shoes, untinted detail (mask_b).

uniform sampler2D mask_a : filter_linear;
uniform sampler2D mask_b : filter_linear;
uniform vec3 skin = vec3(1.0);
uniform vec3 shirt = vec3(1.0);
uniform vec3 pants = vec3(1.0);
uniform vec3 hair = vec3(1.0);
uniform vec3 shoes = vec3(1.0);
uniform vec3 light = vec3(1.0);
uniform float brightness = 1.35;

// In fragment() COLOR already holds the texture's colour, so keep the node's modulate apart.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 shade = texture(TEXTURE, UV);
	vec3 a = texture(mask_a, UV).rgb;
	vec3 b = texture(mask_b, UV).rgb;
	float total = a.r + a.g + a.b + b.r + b.g + b.b;
	vec3 tint = (skin * a.r + shirt * a.g + pants * a.b + hair * b.r + shoes * b.g) * brightness + vec3(b.b);
	tint = total > 0.001 ? tint / total : vec3(1.0);
	COLOR = vec4(shade.rgb * tint * light, shade.a) * modulate;
}
