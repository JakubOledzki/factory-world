shader_type canvas_item;
// Colours one strip of the world map. The texture holds one byte per plot: its biome id. The countries
// texture holds the country of every plot (0 for none), and the map draws their borders. The counties
// texture says which sides of a plot are the border of a town's plots, drawn thinner than a country's.

uniform vec3 colors[13];
uniform sampler2D countries : filter_nearest;
uniform sampler2D counties : filter_nearest;
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

	// County borders: a brick-red line of about a pixel along the flagged sides, half in each plot, fading in
	// from 2 pixels per plot (zoomed out further, towns are dots). Not dark, so it stands out from the plot grid.
	float counties_in = smoothstep(2.0, 4.0, zoom);
	if (counties_in > 0.0) {
		int sides = int(texture(counties, UV).r * 255.0 + 0.5);
		if (sides > 0) {
			vec2 at = fract(plot) * zoom;
			vec2 to = (1.0 - fract(plot)) * zoom;
			float d = 1e6;
			d = (sides & 1) != 0 ? min(d, at.x) : d;
			d = (sides & 2) != 0 ? min(d, to.x) : d;
			d = (sides & 4) != 0 ? min(d, at.y) : d;
			d = (sides & 8) != 0 ? min(d, to.y) : d;
			float line = 1.0 - smoothstep(0.1, 0.9, d);
			color = mix(color, vec3(0.86, 0.42, 0.3), line * counties_in * 0.9);
		}
	}

	// Country borders: a pixel either way lies in another country (both on land), a thin pale line at any zoom.
	vec2 px = 1.0 / (max(zoom, 0.0001) * strip_size);
	float here = texture(countries, UV).r;
	if (here > 0.0) {
		float border = 0.0;
		for (int i = 0; i < 4; i++) {
			vec2 offset = i == 0 ? vec2(px.x, 0.0) : i == 1 ? vec2(-px.x, 0.0) : i == 2 ? vec2(0.0, px.y) : vec2(0.0, -px.y);
			float there = texture(countries, UV + offset).r;
			if (there > 0.0 && abs(there - here) > 0.001) {
				border = 1.0;
			}
		}
		color = mix(color, vec3(0.96, 0.88, 0.66), border * 0.75);
	}

	// Overall a little darker and colder, for the game's night-time look.
	COLOR = vec4(color * vec3(0.86, 0.88, 0.92), 1.0);
}
