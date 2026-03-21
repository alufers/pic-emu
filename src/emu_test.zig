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

    // Status Affected None
}


test "MOVLW instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x42
        \\  END
    );
    defer pic.deinit();
    try pic.execInstruction();

    try std.testing.expectEqual(0x42, pic.REGS.WREG.*);

     // Status Affected None
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

    // Status Affected None
}

test "BNZ instruction - branch taken (Z=0)" {
    // Layout: BNZ skip (0x0000), NOP (0x0002), NOP (0x0004), skip: NOP (0x0006)
    // n=2 → new PC = 0x0002 + 2*2 = 0x0006
    var pic = try asm2emu(
        \\      BNZ skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.Z = 0;
    try pic.execInstruction();

    try std.testing.expectEqual(6, pic.PC);

    // Status Affected: None
}

// test "BNZ instruction - branch not taken (Z=1)" {
//     var pic = try asm2emu(
//         \\      BNZ skip
//         \\      NOP
//         \\      NOP
//         \\  Skip
//         \\      NOP
//         \\  END
//     );
//     defer pic.deinit();
//     pic.REGS.STATUS.*.Z = 1;
//     try pic.execInstruction();

//     try std.testing.expectEqual(2, pic.PC);

//     // Status Affected: None
// }

test "CLRF instruction" {
    var pic = try asm2emu(
        \\      CLRF 0x10, 0
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x5A;
    try pic.execInstruction();

    try std.testing.expectEqual(0x00, pic.MEM[0x10]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);

    // Status Affected: Z
}

test "MOVF instruction" {
    // Four cases stacked: positive->W, zero->W, negative->f, zero->f
    var pic = try asm2emu(
        \\      MOVF 0x10, 0, 0
        \\      MOVF 0x11, 0, 0
        \\      MOVF 0x12, 1, 0
        \\      MOVF 0x13, 1, 0
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x22;
    pic.MEM[0x11] = 0x00;
    pic.MEM[0x12] = 0x80;
    pic.MEM[0x13] = 0x00;

    // Case 1: MOVF 0x10, 0 — positive value to WREG; Z=0 N=0
    try pic.execInstruction();
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 2: MOVF 0x11, 0 — zero value to WREG; Z=1 N=0
    try pic.execInstruction();
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 3: MOVF 0x12, 1 — negative value (MSb=1) written back to f; Z=0 N=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x80, pic.MEM[0x12]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Case 4: MOVF 0x13, 1 — zero written back to f; Z=1 N=0
    try pic.execInstruction();
    try std.testing.expectEqual(0x00, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "LFSR instruction" {
    var pic = try asm2emu(
        \\      LFSR 2, 0x3AB
        \\  END
    );
    defer pic.deinit();
    try pic.execInstruction();

    try std.testing.expectEqual(0x03, pic.REGS.FSR2H.*);
    try std.testing.expectEqual(0xAB, pic.REGS.FSR2L.*);

    // Status Affected None
}

test "MOVFF instruction" {
    var pic = try asm2emu(
        \\      MOVFF 0x100, 0x200
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x100] = 0x33;
    pic.MEM[0x200] = 0x11;
    try pic.execInstruction();

    try std.testing.expectEqual(0x33, pic.MEM[0x100]);
    try std.testing.expectEqual(0x33, pic.MEM[0x200]);

    // Status Affected None
}

test "TBLRD *+ instruction (post-increment)" {
    var pic = try asm2emu(
        \\      TBLRD *+
        \\      ORG 0x100
        \\      DB 0x34
        \\  END
    );
    defer pic.deinit();
    pic.REGS.TBLPTRU.* = 0x00;
    pic.REGS.TBLPTRH.* = 0x01;
    pic.REGS.TBLPTRL.* = 0x00;
    try pic.execInstruction();

    try std.testing.expectEqual(0x34, pic.REGS.TBLAT.*);
    try std.testing.expectEqual(0x00, pic.REGS.TBLPTRU.*);
    try std.testing.expectEqual(0x01, pic.REGS.TBLPTRH.*);
    try std.testing.expectEqual(0x01, pic.REGS.TBLPTRL.*);

    // Status Affected None
}

test "TBLRD +* instruction (pre-increment)" {
    var pic = try asm2emu(
        \\      TBLRD +*
        \\      ORG 0x100
        \\      DB 0x34
        \\  END
    );
    defer pic.deinit();
    pic.REGS.TBLPTRU.* = 0x00;
    pic.REGS.TBLPTRH.* = 0x00;
    pic.REGS.TBLPTRL.* = 0xFF;
    try pic.execInstruction();

    try std.testing.expectEqual(0x34, pic.REGS.TBLAT.*);
    try std.testing.expectEqual(0x00, pic.REGS.TBLPTRU.*);
    try std.testing.expectEqual(0x01, pic.REGS.TBLPTRH.*);
    try std.testing.expectEqual(0x00, pic.REGS.TBLPTRL.*);

    // Status Affected None
}
