shader_type canvas_item;

// Map-cohesion grade for character sprites (players + crowd). Pulls the vivid sprite art toward the
// map's warm palette: a gentle desaturation + a slight warm tint, so characters sit IN the world
// instead of popping out of it (the dev note: "sprites follow the same saturation ramp as the map").
// Identity at saturation=1.0, tint_strength=0.0. The node's own modulate (brighten / smoke fade /
// disguise tint) is preserved because we multiply by COLOR at the end.

uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float luma = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 graded = mix(vec3(luma), tex.rgb, saturation);   // desaturate toward grey
	graded = mix(graded, graded * tint.rgb, tint_strength); // nudge toward the warm map hue
	COLOR = vec4(graded, tex.a) * COLOR;                   // keep the node's modulate
}
