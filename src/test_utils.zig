const std = @import("std");
const pic18 = @import("pic18.zig");

pub fn asm2emu(asm_source: []const u8) !*pic18.PIC18 {
    var tmp_dir = std.testing.tmpDir(.{});

    const prelude =
        \\  RADIX DEC
        \\  ERRORLEVEL  0, -302
        \\  INCLUDE <p18f67k22.inc>
        \\
    ;

    defer tmp_dir.cleanup();
    {
        const src_file = try tmp_dir.dir.createFile(std.testing.io, "a.asm", .{});
        defer src_file.close(std.testing.io);
        try src_file.writeStreamingAll(std.testing.io, prelude);
        try src_file.writeStreamingAll(std.testing.io, asm_source);
    }

    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .cwd = .{ .dir = tmp_dir.dir },
        .argv = &.{ "gpasm", "-p", "18F67K22", "a.asm" },
    });

    defer std.testing.allocator.free(result.stderr);
    defer std.testing.allocator.free(result.stdout);

    switch (result.term) {
        .exited => |ret| {
            if (ret != 0) {
                std.debug.print("\n\n======= GPASM OUT =======\n {s}\n======= END GPASM OUT =======\n", .{result.stdout});
            }
            try std.testing.expectEqual(0, ret);
        },
        else => try std.testing.expect(false),
    }

    var pic = pic18.PIC18.init(std.testing.allocator);

    // load compiled data
    var hexfile = try tmp_dir.dir.openFile(std.testing.io, "a.hex", .{ .mode = .read_only });
    defer hexfile.close(std.testing.io);
    var file_buffer: [1024]u8 = undefined;
    var rdr = hexfile.reader(std.testing.io, &file_buffer);
    try pic.loadRom(&rdr.interface);
    return pic;
}
