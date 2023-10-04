const std = @import("std");
const gl = @import("gl.zig");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const log = std.log.scoped(.gl);

pub fn transpose(comptime n: usize, matrix: [n][n]f32) [n][n]f32 {
    var result: [n][n]f32 = undefined;
    for (0..n) |i| {
        for (0..n) |j| {
            result[j][i] = matrix[i][j];
        }
    }
    return result;
}

pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [4][4]f32 {
    const a = 2.0 / (right - left);
    const b = 2.0 / (top - bottom);
    const c = 2.0 / (near - far);
    const tx = -(right + left) / (right - left);
    const ty = -(top + bottom) / (top - bottom);
    const tz = -(far + near) / (far - near);
    return transpose(4, .{
        .{ a, 0, 0, tx },
        .{ 0, b, 0, ty },
        .{ 0, 0, c, tz },
        .{ 0, 0, 0, 1 },
    });
}

pub const ShaderType = enum(gl.Enum) {
    vertex = gl.VERTEX_SHADER,
    fragment = gl.FRAGMENT_SHADER,
};

pub fn compileShader(shader_type: ShaderType, bytes: []const u8) !u32 {
    const shader = gl.createShader(@intFromEnum(shader_type));

    const version = "#version 120\n";
    const count = 2;
    const strings = [count][*]const u8{ version.ptr, bytes.ptr };
    const lengths = [count]i32{ version.len, @intCast(bytes.len) };
    gl.shaderSource(shader, count, &strings, &lengths);
    gl.compileShader(shader);

    var success: i32 = undefined;
    gl.getShaderiv(shader, gl.COMPILE_STATUS, &success);
    if (success == gl.FALSE) {
        var info_len: i32 = undefined;
        gl.getShaderiv(shader, gl.INFO_LOG_LENGTH, &info_len);

        var info = try game.temp_allocator.alloc(u8, @intCast(info_len));
        gl.getShaderInfoLog(shader, info_len, null, info.ptr);
        info.len -= 1; // null terminator

        log.err("{s} shader compilation failed:\n{s}", .{ @tagName(shader_type), info });
        return error.ShaderCompilationFail;
    }

    return shader;
}

pub const ProgramVars = struct {
    Attrib: type = enum {},
    Uniform: type = enum {},
};

pub fn Program(comptime vars: ProgramVars) type {
    const attribs = std.enums.values(vars.Attrib);
    const uniforms = std.enums.values(vars.Uniform);
    return struct {
        program: u32,
        attribs: [attribs.len]u32,
        uniforms: [uniforms.len]i32,

        const Self = @This();

        pub fn compile(self: *Self, vertex_path: []const u8, fragment_path: []const u8) !void {
            const vertex_bytes = try vfs.readFile(game.temp_allocator, vertex_path);
            const vertex = try compileShader(.vertex, vertex_bytes);
            defer gl.deleteShader(vertex);

            const fragment_bytes = try vfs.readFile(game.temp_allocator, fragment_path);
            const fragment = try compileShader(.fragment, fragment_bytes);
            defer gl.deleteShader(fragment);

            self.program = gl.createProgram();
            gl.attachShader(self.program, vertex);
            gl.attachShader(self.program, fragment);
            gl.linkProgram(self.program);

            for (&self.attribs, attribs) |*out, attrib| {
                out.* = @bitCast(gl.getAttribLocation(self.program, @tagName(attrib)));
            }

            for (&self.uniforms, uniforms) |*out, uniform| {
                out.* = gl.getUniformLocation(self.program, @tagName(uniform));
            }
        }

        pub fn use(self: *Self) void {
            gl.useProgram(self.program);
        }

        pub fn setAttribPointer(self: Self, attrib: vars.Attrib, value: anytype, size: i32, stride: i32) void {
            const index = self.attribs[@intFromEnum(attrib)];
            gl.vertexAttribPointer(index, size, gl.FLOAT, gl.FALSE, stride, value);
        }

        pub fn enableAttribArray(self: Self, attrib: vars.Attrib) void {
            const index = self.attribs[@intFromEnum(attrib)];
            gl.enableVertexAttribArray(index);
        }

        pub fn setUniform(self: Self, uniform: vars.Uniform, value: anytype) void {
            const location = self.uniforms[@intFromEnum(uniform)];
            switch (@TypeOf(value)) {
                comptime_int => gl.uniform1i(location, value),
                [3]f32 => gl.uniform3f(location, value[0], value[1], value[2]),
                *const [4][4]f32 => gl.uniformMatrix4fv(location, 1, gl.FALSE, @ptrCast(value)),
                else => @compileError("unsupported uniform type: " ++ @typeName(@TypeOf(value))),
            }
        }
    };
}

pub const TextureFormat = enum(u16) {
    alpha = gl.ALPHA,
    rgb = gl.RGB,
};

pub fn createTexture(bytes: [*]const u8, width: isize, height: isize, texture_format: TextureFormat) !u32 {
    const format = @intFromEnum(texture_format);

    var texture: u32 = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_2D, texture);

    gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(width), @intCast(height), 0, format, gl.UNSIGNED_BYTE, bytes);

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    return texture;
}
