const std = @import("std");
const freetype = @import("mach-freetype");
const gl = @import("gl.zig");
const glw = @import("glw.zig");
const vfs = @import("vfs.zig");
const game = @import("game.zig");
const renderer = @import("renderer.zig");

var face: freetype.Face = undefined;

var program: glw.Program("text", .{
    .Attrib = enum { vertex },
    .Uniform = enum { projection, texture, color },
}) = undefined;

pub fn init() !void {
    const ft = try freetype.Library.init();

    face = try ft.createFaceMemory(@embedFile("assets/fonts/NotoSansJP-Regular.ttf"), 0);

    try program.compile();
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

        const result = RenderedChar{
            .advance = fixed6(glyph.advance().x),
            .bitmap = if (bitmap.buffer()) |buffer| .{
                .texture = try glw.createTexture(buffer.ptr, bitmap.width(), bitmap.rows(), .alpha),
                .width = @floatFromInt(bitmap.width()),
                .height = @floatFromInt(bitmap.rows()),
                .offset_x = @floatFromInt(glyph.bitmapLeft()),
                .offset_y = @floatFromInt(glyph.bitmapTop()),
            } else null,
        };

        try cache.put(.{ char, size }, result);
        return result;
    };
}

pub fn draw(text: []const u8, start_x: f32, start_y: f32, color: [3]f32) !f32 {
    program.use();
    program.setUniform(.projection, &renderer.ortho);
    program.setUniform(.color, color);

    const size = face.size().metrics().y_ppem;
    var x = start_x;
    var y = renderer.height - start_y;
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

    return x;
}

pub var height: f32 = undefined;

pub fn setSize(size: u32) !void {
    try face.setPixelSizes(size, size);
    height = fixed6(face.size().metrics().height);
}

fn fixed6(value: c_long) f32 {
    return @as(f32, @floatFromInt(value)) / 64;
}
