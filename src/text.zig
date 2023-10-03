const std = @import("std");
const freetype = @import("mach-freetype");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");

pub var face: freetype.Face = undefined;

var program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture, color },
}) = undefined;

pub fn init() !void {
    const ft = try freetype.Library.init();

    const path = try vfs.absolutePath("NotoSansJP-Regular.ttf");
    face = try ft.createFace(path, 0);

    const vertex_bytes = try vfs.readFile(game.temp_allocator, "shaders/text.vert");
    const fragment_bytes = try vfs.readFile(game.temp_allocator, "shaders/text.frag");
    try program.create(vertex_bytes, fragment_bytes);
    program.enableAttribArray(.vertex);
}

const RenderedChar = struct {
    advance: f32,
    bitmap: ?Bitmap,

    const Bitmap = struct {
        texture: u32,
        width: f32,
        height: f32,
        offset_x: f32,
        offset_y: f32,
    };
};

var cache = std.AutoHashMap(struct { u21, u16 }, RenderedChar).init(game.allocator);

fn loadChar(char: u21, size: u16) !RenderedChar {
    return cache.get(.{ char, size }) orelse {
        try face.setPixelSizes(size, size);
        try face.loadChar(char, .{ .render = true });
        const glyph = face.glyph();
        const bitmap = glyph.bitmap().handle;

        var result: RenderedChar = .{ .advance = @floatFromInt(glyph.advance().x >> 6), .bitmap = null };

        if (bitmap.buffer) |buffer| {
            const texture = try glw.createTexture(buffer, bitmap.width, bitmap.rows, .alpha);
            result.bitmap = .{
                .texture = texture,
                .width = @floatFromInt(bitmap.width),
                .height = @floatFromInt(bitmap.rows),
                .offset_x = @floatFromInt(glyph.bitmapLeft()),
                .offset_y = @floatFromInt(glyph.bitmapTop()),
            };
        }

        try cache.put(.{ char, size }, result);
        return result;
    };
}

pub fn draw(text: []const u8, size: u16, start_x: u16, start_y: u16) !void {
    program.use();

    const window_size = game.window.getSize();
    gl.viewport(0, 0, @bitCast(window_size.width), @bitCast(window_size.height));
    const ortho = glw.ortho(0, @floatFromInt(window_size.width), 0, @floatFromInt(window_size.height), 1, -1);
    program.setUniform(.projection, &ortho);

    var current_x: f32 = @floatFromInt(start_x);
    var current_y: f32 = @floatFromInt(window_size.height);
    current_y -= @floatFromInt(start_y);
    current_y -= @floatFromInt(size);

    const view = try std.unicode.Utf8View.init(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        const glyph = try loadChar(cp, size);

        if (glyph.bitmap) |bitmap| {
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, bitmap.texture);
            program.setUniform(.texture, 0);

            program.setUniform(.color, [3]f32{ 1, 1, 1 });

            const x = current_x + bitmap.offset_x;
            const y = current_y + bitmap.offset_y - bitmap.height;

            const vertices = [_]f32{
                x,                y,                 0, 1,
                x,                y + bitmap.height, 0, 0,
                x + bitmap.width, y + bitmap.height, 1, 0,
                x + bitmap.width, y,                 1, 1,
            };

            program.setAttribPointer(.vertex, &vertices, 4, 0);

            const indices = [_]u8{
                0, 1, 2,
                0, 2, 3,
            };

            gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_BYTE, &indices);
        }

        current_x += glyph.advance;
    }
}
