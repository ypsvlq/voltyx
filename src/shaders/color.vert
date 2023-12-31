attribute vec4 vertex;
uniform mat4x4 projection;
uniform mat4x4 view;

void main() {
	gl_Position = projection * view * vec4(vertex.xy, 0, 1);
}
