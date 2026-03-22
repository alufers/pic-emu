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
        \\      MOVWF 0x10, 0
        \\  END
    );
    defer pic.deinit();
    try pic.execInstruction();
    try pic.execInstruction();

    try std.testing.expectEqual(0x42, pic.MEM[0x10]);

    // Status Affected None
}

test "DECF instruction" {
    // Six cases covering both destinations and all status bits.
    // PIC18 carry convention for subtraction: C=1 no borrow, C=0 borrow.
    // Same for DC: DC=1 no digit borrow, DC=0 digit borrow.
    var pic = try asm2emu(
        \\      DECF 0x10, 1, 0    ; d=1: result to f, normal decrement
        \\      DECF 0x11, 0, 0    ; d=0: result to W, f must be unchanged
        \\      DECF 0x12, 1, 0    ; 0x01 -> 0x00: Z=1
        \\      DECF 0x13, 1, 0    ; 0x00 -> 0xFF: borrow C=0, N=1
        \\      DECF 0x14, 1, 0    ; 0x80 -> 0x7F: signed OV=1, digit borrow DC=0
        \\      DECF 0x15, 1, 0    ; 0x10 -> 0x0F: digit borrow DC=0, no borrow C=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x05;
    pic.MEM[0x11] = 0x05;
    pic.MEM[0x12] = 0x01;
    pic.MEM[0x13] = 0x00;
    pic.MEM[0x14] = 0x80;
    pic.MEM[0x15] = 0x10;

    // Case 1: d=1, 0x05 -> 0x04, result to f
    try pic.execInstruction();
    try std.testing.expectEqual(0x04, pic.MEM[0x10]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);  // no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // no digit borrow

    // Case 2: d=0, 0x05 -> 0x04, result to W; f must stay 0x05
    try pic.execInstruction();
    try std.testing.expectEqual(0x04, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x05, pic.MEM[0x11]);

    // Case 3: 0x01 -> 0x00, Z=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x00, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);  // no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // no digit borrow

    // Case 4: 0x00 -> 0xFF, unsigned borrow: C=0, N=1
    try pic.execInstruction();
    try std.testing.expectEqual(0xFF, pic.MEM[0x13]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV); // no signed overflow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);  // borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // digit borrow

    // Case 5: 0x80 -> 0x7F, signed overflow: OV=1, N=0, digit borrow: DC=0
    try pic.execInstruction();
    try std.testing.expectEqual(0x7F, pic.MEM[0x14]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);  // no borrow (0x80 > 0)
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // lower nibble 0-1 borrows

    // Case 6: 0x10 -> 0x0F, only digit borrow: DC=0, C=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x0F, pic.MEM[0x15]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);  // no borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // digit borrow

    // Status Affected: C, DC, N, OV, Z
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

test "BNZ instruction - branch not taken (Z=1)" {
    var pic = try asm2emu(
        \\      BNZ skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.Z = 1;
    try pic.execInstruction();

    try std.testing.expectEqual(2, pic.PC);

    // Status Affected: None
}

test "indirect register addressing (INDF/POSTINC/POSTDEC/PREINC/PLUSW for FSR0,1,2)" {
    // FSR0=0x10, FSR1=0x20, FSR2=0x30, WREG offset for PLUSW=5
    //
    // FSR0 state trace:
    //   INDF0:    reads MEM[0x10]=0xA0, FSR0=0x10
    //   POSTINC0: reads MEM[0x10]=0xA0, FSR0->0x11
    //   POSTDEC0: reads MEM[0x11]=0xA1, FSR0->0x10
    //   PREINC0:  FSR0->0x11, reads MEM[0x11]=0xA1
    //   PLUSW0:   reads MEM[0x11+5]=MEM[0x16]=0xA6, FSR0=0x11
    // Same pattern for FSR1 (0xB_) and FSR2 (0xC_).
    var pic = try asm2emu(
        \\      MOVF INDF0, 0, 0
        \\      MOVWF 0x50, 0
        \\      MOVF POSTINC0, 0, 0
        \\      MOVWF 0x51, 0
        \\      MOVF POSTDEC0, 0, 0
        \\      MOVWF 0x52, 0
        \\      MOVF PREINC0, 0, 0
        \\      MOVWF 0x53, 0
        \\      MOVLW 5
        \\      MOVF PLUSW0, 0, 0
        \\      MOVWF 0x54, 0
        \\      MOVF INDF1, 0, 0
        \\      MOVWF 0x55, 0
        \\      MOVF POSTINC1, 0, 0
        \\      MOVWF 0x56, 0
        \\      MOVF POSTDEC1, 0, 0
        \\      MOVWF 0x57, 0
        \\      MOVF PREINC1, 0, 0
        \\      MOVWF 0x58, 0
        \\      MOVLW 5
        \\      MOVF PLUSW1, 0, 0
        \\      MOVWF 0x59, 0
        \\      MOVF INDF2, 0, 0
        \\      MOVWF 0x5A, 0
        \\      MOVF POSTINC2, 0, 0
        \\      MOVWF 0x5B, 0
        \\      MOVF POSTDEC2, 0, 0
        \\      MOVWF 0x5C, 0
        \\      MOVF PREINC2, 0, 0
        \\      MOVWF 0x5D, 0
        \\      MOVLW 5
        \\      MOVF PLUSW2, 0, 0
        \\      MOVWF 0x5E, 0
        \\  END
    );
    defer pic.deinit();

    pic.REGS.FSR0H.* = 0x00;
    pic.REGS.FSR0L.* = 0x10;
    pic.REGS.FSR1H.* = 0x00;
    pic.REGS.FSR1L.* = 0x20;
    pic.REGS.FSR2H.* = 0x00;
    pic.REGS.FSR2L.* = 0x30;

    // FSR0 region
    pic.MEM[0x10] = 0xA0; // INDF0, POSTINC0
    pic.MEM[0x11] = 0xA1; // POSTDEC0, PREINC0
    pic.MEM[0x16] = 0xA6; // PLUSW0 (FSR0=0x11, W=5 → 0x16)
    // FSR1 region
    pic.MEM[0x20] = 0xB0; // INDF1, POSTINC1
    pic.MEM[0x21] = 0xB1; // POSTDEC1, PREINC1
    pic.MEM[0x26] = 0xB6; // PLUSW1 (FSR1=0x21, W=5 → 0x26)
    // FSR2 region
    pic.MEM[0x30] = 0xC0; // INDF2, POSTINC2
    pic.MEM[0x31] = 0xC1; // POSTDEC2, PREINC2
    pic.MEM[0x36] = 0xC6; // PLUSW2 (FSR2=0x31, W=5 → 0x36)

    for (0..33) |_| try pic.execInstruction();

    // FSR0 results
    try std.testing.expectEqual(0xA0, pic.MEM[0x50]); // INDF0
    try std.testing.expectEqual(0xA0, pic.MEM[0x51]); // POSTINC0 (reads before increment)
    try std.testing.expectEqual(0xA1, pic.MEM[0x52]); // POSTDEC0 (FSR0 was 0x11 after POSTINC)
    try std.testing.expectEqual(0xA1, pic.MEM[0x53]); // PREINC0 (increments to 0x11 first)
    try std.testing.expectEqual(0xA6, pic.MEM[0x54]); // PLUSW0 (0x11+5=0x16)
    // FSR1 results
    try std.testing.expectEqual(0xB0, pic.MEM[0x55]); // INDF1
    try std.testing.expectEqual(0xB0, pic.MEM[0x56]); // POSTINC1
    try std.testing.expectEqual(0xB1, pic.MEM[0x57]); // POSTDEC1
    try std.testing.expectEqual(0xB1, pic.MEM[0x58]); // PREINC1
    try std.testing.expectEqual(0xB6, pic.MEM[0x59]); // PLUSW1 (0x21+5=0x26)
    // FSR2 results
    try std.testing.expectEqual(0xC0, pic.MEM[0x5A]); // INDF2
    try std.testing.expectEqual(0xC0, pic.MEM[0x5B]); // POSTINC2
    try std.testing.expectEqual(0xC1, pic.MEM[0x5C]); // POSTDEC2
    try std.testing.expectEqual(0xC1, pic.MEM[0x5D]); // PREINC2
    try std.testing.expectEqual(0xC6, pic.MEM[0x5E]); // PLUSW2 (0x31+5=0x36)
    // Final FSR states (each left at base+1 after PREINC, PLUSW does not modify)
    try std.testing.expectEqual(0x11, pic.REGS.FSR0L.*);
    try std.testing.expectEqual(0x21, pic.REGS.FSR1L.*);
    try std.testing.expectEqual(0x31, pic.REGS.FSR2L.*);
}

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
