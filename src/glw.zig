const std = @import("std");
const img = @import("zigimg");
const gl = @import("gl.zig");
const game = @import("game.zig");
const vfs = @import("vfs.zig");
const log = std.log.scoped(.gl);

pub fn radians(degrees: f32) f32 {
    return degrees * std.math.pi / 180;
}

pub fn transpose(matrix: [4][4]f32) [4][4]f32 {
    var result: [4][4]f32 = undefined;
    for (0..4) |i| {
        for (0..4) |j| {
            result[j][i] = matrix[i][j];
        }
    }
    return result;
}

pub fn multiply(a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
    var result = std.mem.zeroes([4][4]f32);
    for (0..4) |i| {
        for (0..4) |j| {
            for (0..4) |k| {
                result[i][j] += a[i][k] * b[k][j];
            }
        }
    }
    return result;
}

pub fn translation(v: [3]f32) [4][4]f32 {
    return transpose(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ v[0], v[1], v[2], 1 },
    });
}

pub fn rotationX(angle: f32) [4][4]f32 {
    const s = @sin(angle);
    const c = @cos(angle);
    return transpose(.{
        .{ 1, 0, 0, 0 },
        .{ 0, c, s, 0 },
        .{ 0, -s, c, 0 },
        .{ 0, 0, 0, 1 },
    });
}

pub fn rotationY(angle: f32) [4][4]f32 {
    const s = @sin(angle);
    const c = @cos(angle);
    return transpose(.{
        .{ c, 0, -s, 0 },
        .{ 0, 1, 0, 0 },
        .{ s, 0, c, 0 },
        .{ 0, 0, 0, 1 },
    });
}

pub fn rotationZ(angle: f32) [4][4]f32 {
    const s = @sin(angle);
    const c = @cos(angle);
    return transpose(.{
        .{ c, s, 0, 0 },
        .{ -s, c, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    });
}

pub fn ortho(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [4][4]f32 {
    const a = 2.0 / (right - left);
    const b = 2.0 / (top - bottom);
    const c = 2.0 / (near - far);
    const tx = -(right + left) / (right - left);
    const ty = -(top + bottom) / (top - bottom);
    const tz = -(far + near) / (far - near);
    return transpose(.{
        .{ a, 0, 0, tx },
        .{ 0, b, 0, ty },
        .{ 0, 0, c, tz },
        .{ 0, 0, 0, 1 },
    });
}

pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) [4][4]f32 {
    const fov_radians = radians(fov);
    const f = 1 / @tan(fov_radians / 2);
    return transpose(.{
        .{ f / aspect, 0, 0, 0 },
        .{ 0, f, 0, 0 },
        .{ 0, 0, (far + near) / (near - far), (2 * far * near) / (near - far) },
        .{ 0, 0, -1, 0 },
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

            const program = gl.createProgram();
            errdefer gl.deleteProgram(program);
            gl.attachShader(program, vertex);
            gl.attachShader(program, fragment);
            gl.linkProgram(program);

            var success: i32 = undefined;
            gl.getProgramiv(program, gl.LINK_STATUS, &success);
            if (success == gl.FALSE) {
                var info_len: i32 = undefined;
                gl.getProgramiv(program, gl.INFO_LOG_LENGTH, &info_len);

                var info = try game.temp_allocator.alloc(u8, @intCast(info_len));
                gl.getProgramInfoLog(program, info_len, null, info.ptr);
                info.len -= 1; // null terminator

                log.err("program link failed:\n{s}", .{info});
                return error.ProgramLinkFail;
            }

            self.program = program;

            for (&self.attribs, attribs) |*out, attrib| {
                out.* = @bitCast(gl.getAttribLocation(program, @tagName(attrib)));
            }

            for (&self.uniforms, uniforms) |*out, uniform| {
                out.* = gl.getUniformLocation(program, @tagName(uniform));
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
    rgba = gl.RGBA,
};

pub fn createTexture(bytes: [*]const u8, width: usize, height: usize, texture_format: TextureFormat) !u32 {
    const format = @intFromEnum(texture_format);

    var texture: u32 = undefined;
    gl.genTextures(1, &texture);
    gl.bindTexture(gl.TEXTURE_2D, texture);

    gl.texImage2D(gl.TEXTURE_2D, 0, format, @intCast(width), @intCast(height), 0, format, gl.UNSIGNED_BYTE, bytes);
    gl.generateMipmap(gl.TEXTURE_2D);

    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

    return texture;
}

pub fn loadPNG(path: []const u8) !u32 {
    const file = try vfs.openFile(path);
    defer file.close();

    var stream = std.io.StreamSource{ .file = file };
    const image = try img.png.PNG.readImage(game.temp_allocator, &stream);

    const format: TextureFormat = switch (image.pixelFormat()) {
        .grayscale8 => .alpha,
        .rgb24 => .rgb,
        .rgba32 => .rgba,
        else => return error.UnsupportedPixelFormat,
    };

    return createTexture(image.rawBytes().ptr, image.width, image.height, format);
}
