const std = @import("std");
const zigimg = @import("zigimg");
const gl = @import("../../gl.zig");
const game = @import("../../game.zig");
const vfs = @import("../../vfs.zig");
const glw = @import("../../glw.zig");

var default: u32 = undefined;
var cache = std.StringHashMap([4]u32).init(game.allocator);

var queue = std.StringHashMap(?[4]?zigimg.ImageUnmanaged).init(game.allocator);
var mutex = std.Thread.Mutex{};
var condition = std.Thread.Condition{};
var working = true;

pub fn init() !void {
    default = try glw.loadEmbeddedPNG("jacket.png");
    _ = try std.Thread.spawn(.{}, thread, .{});
}

pub fn clear() void {
    mutex.lock();
    defer mutex.unlock();
    while (working) condition.wait(&mutex);

    var cache_iter = cache.valueIterator();
    while (cache_iter.next()) |textures| {
        var last = default;
        for (textures.*) |texture| {
            if (texture != last) {
                last = texture;
                gl.deleteTextures(1, &texture);
            }
        }
    }
    cache.clearRetainingCapacity();

    var queue_iter = queue.valueIterator();
    while (queue_iter.next()) |maybe_images| {
        if (maybe_images.*) |*images| {
            for (images) |*maybe_image| {
                if (maybe_image.*) |*image| {
                    image.deinit(game.allocator);
                }
            }
        }
    }
    queue.clearRetainingCapacity();
}

pub fn get(name: []const u8, difficulty: u2) !u32 {
    if (cache.get(name)) |jackets| return jackets[difficulty];

    mutex.lock();
    defer mutex.unlock();
    if (queue.getEntry(name)) |entry| {
        if (entry.value_ptr.*) |*images| {
            var jackets: [4]u32 = undefined;
            var last: u32 = default;
            for (&jackets, images) |*jacket, *image_ptr| {
                if (image_ptr.*) |*image| {
                    last = try glw.createImageTexture(image.*);
                    image.deinit(game.allocator);
                }
                jacket.* = last;
            }
            try cache.put(name, jackets);
            queue.removeByPtr(entry.key_ptr);
            return jackets[difficulty];
        }
    } else {
        try queue.put(name, null);
        condition.signal();
    }
    return default;
}

fn thread() void {
    mutex.lock();
    while (true) {
        var iter = queue.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* == null) {
                const name = entry.key_ptr.*;
                mutex.unlock();
                var images: [4]?zigimg.ImageUnmanaged = @splat(null);
                for (&images, 1..) |*image, i| {
                    const path = std.fmt.allocPrint(game.allocator, "songs/{s}/{}.png", .{ name, i }) catch continue;
                    defer game.allocator.free(path);
                    const file = vfs.openFile(path) catch continue;
                    defer file.close();
                    var stream = std.io.StreamSource{ .file = file };
                    image.* = zigimg.png.PNG.readImage(game.allocator, &stream) catch continue;
                }
                mutex.lock();
                queue.getPtr(name).?.* = images;
                iter = queue.iterator();
            }
        }
        working = false;
        condition.signal();
        condition.wait(&mutex);
        working = true;
    }
}
