shader_type canvas_item;
// Colours one strip of the world map. The texture holds one byte per plot: its biome id.

uniform vec3 colors[13];
// Plots in this strip of the map, and the column it starts at.
uniform vec2 strip_size;
uniform int strip_from = 0;
// Screen pixels per plot.
uniform float zoom = 1.0;

// Whether the desert plot is an oasis: the server's hash (Oasis.Is), in 32-bit unsigned arithmetic.
bool oasis(vec2 uv) {
	uvec2 p = uvec2(floor(uv * strip_size)) + uvec2(uint(strip_from), 0u);
	uint h = p.x * 374761393u + p.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	h ^= h >> 16u;
	return h % 100u < 4u;
}

vec3 biome_color(sampler2D biomes, vec2 uv) {
	int id = int(texture(biomes, uv).r * 255.0 + 0.5);
	if (id == 5 && oasis(uv)) {
		id = 12;
	}
	return colors[clamp(id, 0, 12)];
}

void fragment() {
	vec2 plot = UV * strip_size;
	vec3 color;
	if (zoom < 1.0) {
		// Zoomed out a pixel covers several plots: average a few so coasts don't flicker.
		vec2 d = 0.35 / (zoom * strip_size);
		color = (biome_color(TEXTURE, UV + vec2(-d.x, -d.y)) + biome_color(TEXTURE, UV + vec2(d.x, -d.y))
			+ biome_color(TEXTURE, UV + vec2(-d.x, d.y)) + biome_color(TEXTURE, UV + vec2(d.x, d.y))) * 0.25;
	} else {
		color = biome_color(TEXTURE, UV);
		// A little grain per plot, so a large forest isn't one flat colour.
		float grain = fract(sin(dot(floor(plot), vec2(12.9898, 78.233))) * 43758.5453);
		color *= 0.93 + 0.1 * grain;
	}

	// Plot borders, fading in from 6 pixels per plot.
	float lines = smoothstep(6.0, 14.0, zoom);
	if (lines > 0.0) {
		vec2 edge = min(fract(plot), 1.0 - fract(plot)) * zoom;
		float border = 1.0 - smoothstep(0.0, 1.0, min(edge.x, edge.y));
		color = mix(color, color * 0.55, border * lines * 0.8);
	}

	// Overall a little darker and colder, for the game's night-time look.
	COLOR = vec4(color * vec3(0.86, 0.88, 0.92), 1.0);
}
