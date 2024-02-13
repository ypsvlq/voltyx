attribute vec4 vertex;
uniform mat4 projection;
uniform mat4 view;

void main() {
    gl_Position = projection * view * vec4(vertex.xy, 0.0, 1.0);
}
