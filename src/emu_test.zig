const std = @import("std");
const main = @import("main.zig");

fn asm2emu(asm_source: []const u8) !main.PIC18 {
    var tmp_dir = std.testing.tmpDir(.{});

    const prelude =
        \\  RADIX DEC
        \\  ERRORLEVEL  0, -302
        \\  INCLUDE <p18f67k22.inc>
        \\
    ;

    defer tmp_dir.cleanup();
    {
        const src_file = try tmp_dir.dir.createFile("a.asm", .{});
        defer src_file.close();
        try src_file.writeAll(prelude);
        try src_file.writeAll(asm_source);
    }

    const result = try std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .cwd_dir = tmp_dir.dir,
        .argv = &.{ "gpasm", "-p", "18F67K22", "a.asm" },
    });

    defer std.testing.allocator.free(result.stderr);
    defer std.testing.allocator.free(result.stdout);

    switch (result.term) {
        .Exited => |ret| {
            if (ret != 0) {
                std.debug.print("\n\n======= GPASM OUT =======\n {s}\n======= END GPASM OUT =======\n", .{result.stdout});
            }
            try std.testing.expectEqual(0, ret);
        },
        else => try std.testing.expect(false),
    }

    var pic = main.PIC18.init(std.testing.allocator);

    // load compiled data
    var hexfile = try tmp_dir.dir.openFile("a.hex", .{ .mode = .read_only });
    defer hexfile.close();
    var file_buffer: [1024]u8 = undefined;
    var rdr = hexfile.reader(&file_buffer);
    try pic.loadRom(&rdr.interface);
    return pic;
}

test "GOTO instruction" {
    var pic = try asm2emu(
        \\      GOTO 38
        \\  END
    );
    defer pic.deinit();
    try pic.execInstruction();

    try std.testing.expectEqual(pic.PC, 38);

    // Status Affected	None
}


test "MOVLW instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x42
        \\  END
    );
    defer pic.deinit();
    try pic.execInstruction();

    try std.testing.expectEqual(0x42, pic.REGS.WREG.*);

     // Status Affected	None
}

test "MOVWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x42
        \\      MOVWF 0xdc, 0
        \\  END
    );
    defer pic.deinit();
    try pic.execInstruction();
    try pic.execInstruction();

    try std.testing.expectEqual(0x42, pic.MEM[0xfdc]);

    // Status Affected	None
}
