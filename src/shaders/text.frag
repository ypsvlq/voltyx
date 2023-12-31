varying vec2 uv;
uniform sampler2D texture;
uniform vec3 color;

void main() {
	float alpha = texture2D(texture, uv).a;
	gl_FragColor = vec4(color, alpha);
}
