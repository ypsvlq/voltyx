varying vec2 uv;
uniform sampler2D texture;
uniform vec3 left_color;
uniform vec3 right_color;

const vec3 track_color = vec3(0.9);

void main() {
	vec3 sample = texture2D(texture, uv).rgb;
	vec3 color = left_color * sample.b + track_color * sample.g + right_color * sample.r;
	gl_FragColor = vec4(color, 1);
}
