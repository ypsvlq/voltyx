const std = @import("std");
const freetype = @import("mach-freetype");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const renderer = @import("renderer.zig");

var face: freetype.Face = undefined;

var program: glw.Program(.{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture, color },
}) = undefined;

pub fn init() !void {
    const ft = try freetype.Library.init();

    const path = try vfs.absolutePath("fonts/NotoSansJP-Regular.ttf");
    face = try ft.createFace(path, 0);

    try program.compile("shaders/text.vert", "shaders/text.frag");
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
        const bitmap = glyph.bitmap();

        var result: RenderedChar = .{ .advance = @floatFromInt(glyph.advance().x >> 6), .bitmap = null };

        if (bitmap.buffer()) |buffer| {
            const texture = try glw.createTexture(buffer.ptr, bitmap.width(), bitmap.rows(), .alpha);
            result.bitmap = .{
                .texture = texture,
                .width = @floatFromInt(bitmap.width()),
                .height = @floatFromInt(bitmap.rows()),
                .offset_x = @floatFromInt(glyph.bitmapLeft()),
                .offset_y = @floatFromInt(glyph.bitmapTop()),
            };
        }

        try cache.put(.{ char, size }, result);
        return result;
    };
}

pub fn draw(text: []const u8, start_x: u16, start_y: u16, color: [3]f32) !u16 {
    program.use();
    program.setUniform(.projection, &renderer.ortho);
    program.setUniform(.color, color);

    const size = face.size().metrics().y_ppem;

    var x: f32 = @floatFromInt(start_x);
    var y = renderer.height;
    y -= @floatFromInt(start_y);
    y -= @floatFromInt(size);

    const view = try std.unicode.Utf8View.init(text);
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        const glyph = try loadChar(cp, size);

        if (glyph.bitmap) |bitmap| {
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, bitmap.texture);
            program.setUniform(.texture, 0);

            renderer.drawQuad(
                program,
                x + bitmap.offset_x,
                y + bitmap.offset_y - bitmap.height,
                bitmap.width,
                bitmap.height,
            );
        }

        x += glyph.advance;
    }

    return @intFromFloat(x);
}

pub fn setSize(size: u32) !void {
    try face.setPixelSizes(size, size);
}

pub fn getLineHeight() c_long {
    return face.size().metrics().height >> 6;
}
