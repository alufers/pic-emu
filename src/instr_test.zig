const std = @import("std");
const main = @import("main.zig");
const test_utils = @import("test_utils.zig");

const asm2emu = test_utils.asm2emu;

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

test "SETF instruction" {
    var pic = try asm2emu(
        \\      SETF 0x10, 0    ; access bank -> 0xFF
        \\      MOVLB 5
        \\      SETF 0x20, 1   ; BSR bank 5 -> 0xFF
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x00;
    pic.MEM[0x520] = 0x00;

    try pic.execInstruction();
    try std.testing.expectEqual(0xFF, pic.MEM[0x10]);

    try pic.execInstruction(); // MOVLB 5
    try pic.execInstruction(); // SETF 0x20, 1
    try std.testing.expectEqual(0xFF, pic.MEM[0x520]);

    // Status Affected: None
}

test "BCF instruction" {
    var pic = try asm2emu(
        \\      BCF 0x10, 7, 0    ; doc example: clear bit 7 of 0xC7 -> 0x47
        \\      BCF 0x11, 3, 0    ; clear bit 3 of 0xFF -> 0xF7
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xC7;
    pic.MEM[0x11] = 0xFF;

    // Doc example: 0xC7 = 1100_0111, clear bit 7 -> 0100_0111 = 0x47
    try pic.execInstruction();
    try std.testing.expectEqual(0x47, pic.MEM[0x10]);

    // 0xFF = 1111_1111, clear bit 3 -> 1111_0111 = 0xF7
    try pic.execInstruction();
    try std.testing.expectEqual(0xF7, pic.MEM[0x11]);

    // Status Affected: None
}

test "BSF instruction" {
    var pic = try asm2emu(
        \\      BSF 0x10, 7, 0    ; doc example: 0x0A | bit7 = 0x8A, access bank
        \\      BSF 0x11, 0, 0    ; set bit 0 of 0xF0 -> 0xF1
        \\      BSF 0x12, 3, 0    ; set already-set bit: 0xFF -> 0xFF
        \\      MOVLB 2
        \\      BSF 0x20, 4, 1   ; 0x01 | bit4 = 0x11, BSR bank 2
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x0A;
    pic.MEM[0x11] = 0xF0;
    pic.MEM[0x12] = 0xFF;
    pic.MEM[0x220] = 0x01;

    try pic.execInstruction();
    try std.testing.expectEqual(0x8A, pic.MEM[0x10]);

    try pic.execInstruction();
    try std.testing.expectEqual(0xF1, pic.MEM[0x11]);

    try pic.execInstruction();
    try std.testing.expectEqual(0xFF, pic.MEM[0x12]);

    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // BSF 0x20, 4, 1
    try std.testing.expectEqual(0x11, pic.MEM[0x220]);

    // Status Affected: None
}

test "BTG instruction" {
    var pic = try asm2emu(
        \\      BTG 0x10, 4, 0    ; doc example: 0x75 toggle bit4 = 0x65, access bank
        \\      BTG 0x11, 0, 0    ; toggle bit 0 of 0xF0 -> 0xF1
        \\      BTG 0x11, 0, 0    ; toggle back -> 0xF0
        \\      MOVLB 3
        \\      BTG 0x20, 7, 1   ; 0x0F toggle bit7 = 0x8F, BSR bank 3
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x75;
    pic.MEM[0x11] = 0xF0;
    pic.MEM[0x320] = 0x0F;

    try pic.execInstruction();
    try std.testing.expectEqual(0x65, pic.MEM[0x10]);

    try pic.execInstruction();
    try std.testing.expectEqual(0xF1, pic.MEM[0x11]);

    try pic.execInstruction();
    try std.testing.expectEqual(0xF0, pic.MEM[0x11]);

    try pic.execInstruction(); // MOVLB 3
    try pic.execInstruction(); // BTG 0x20, 7, 1
    try std.testing.expectEqual(0x8F, pic.MEM[0x320]);

    // Status Affected: None
}

test "BTFSC instruction" {
    var pic = try asm2emu(
        \\      BTFSC 0x10, 3, 0   ; bit 3 of 0x00 = 0 -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x11         ; WREG = 0x11 (skip happened)
        \\      BTFSC 0x11, 3, 0   ; bit 3 of 0x08 = 1 -> no skip
        \\      MOVLW 0x22         ; WREG = 0x22 (no skip)
        \\      MOVLB 2
        \\      BTFSC 0x20, 5, 1   ; bit 5 of MEM[0x220]=0x03 = 0 -> skip, BSR bank 2
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x44         ; WREG = 0x44 (skip happened)
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x00; // bit 3 = 0 -> skip
    pic.MEM[0x11] = 0x08; // bit 3 = 1 -> no skip
    pic.MEM[0x220] = 0x03; // bit 5 = 0 -> skip

    try pic.execInstruction(); // BTFSC 0x10, 3 -> skip
    try pic.execInstruction(); // MOVLW 0x11
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);

    try pic.execInstruction(); // BTFSC 0x11, 3 -> no skip
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // BTFSC 0x20, 5, 1 -> skip
    try pic.execInstruction(); // MOVLW 0x44
    try std.testing.expectEqual(0x44, pic.REGS.WREG.*);

    // Status Affected: None
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
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow
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
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // no digit borrow

    // Case 4: 0x00 -> 0xFF, unsigned borrow: C=0, N=1
    try pic.execInstruction();
    try std.testing.expectEqual(0xFF, pic.MEM[0x13]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV); // no signed overflow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // digit borrow

    // Case 5: 0x80 -> 0x7F, signed overflow: OV=1, N=0, digit borrow: DC=0
    try pic.execInstruction();
    try std.testing.expectEqual(0x7F, pic.MEM[0x14]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow (0x80 > 0)
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // lower nibble 0-1 borrows

    // Case 6: 0x10 -> 0x0F, only digit borrow: DC=0, C=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x0F, pic.MEM[0x15]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow
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

test "BRA instruction - forward and backward branch" {
    var pic = try asm2emu(
        \\      BRA forward        ; forward: skip trap
        \\      MOVLW 0xFF         ; trap
        \\forward:
        \\      MOVLW 0x11         ; WREG = 0x11
        \\      BRA skip_backward  ; skip over back_here
        \\back_here:
        \\      MOVLW 0x22         ; WREG = 0x22, reached via backward branch
        \\      BRA done
        \\skip_backward:
        \\      BRA back_here      ; backward branch
        \\done:
        \\      NOP
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // BRA forward (skip trap)
    try pic.execInstruction(); // MOVLW 0x11
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*); // trap was skipped

    try pic.execInstruction(); // BRA skip_backward
    try pic.execInstruction(); // BRA back_here (backward branch)
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*); // backward branch worked

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
    // Six cases covering both destinations and both addressing modes.
    // d=0 → result to WREG, f must be unchanged.
    // d=1 → result written back to f, WREG must be unchanged (sentinel check).
    // a=0 → Access Bank. a=1 → BSR bank (MOVLB 3 → bank offset 0x300).
    //
    // Each d=0 case is preceded by MOVLW to poison WREG so we can see it change.
    // Each d=1 case is preceded by MOVLW to load a sentinel we can verify is untouched.
    var pic = try asm2emu(
        \\      MOVLW 0xFF
        \\      MOVF 0x10, 0, 0    ; d=0 a=0: positive -> WREG
        \\      MOVLW 0xBB
        \\      MOVF 0x11, 1, 0    ; d=1 a=0: zero written back to f
        \\      MOVLW 0x00
        \\      MOVF 0x12, 0, 0    ; d=0 a=0: negative (MSb=1) -> WREG
        \\      MOVLW 0xAA
        \\      MOVF 0x13, 1, 0    ; d=1 a=0: non-zero written back to f
        \\      MOVLB 3
        \\      MOVLW 0x00
        \\      MOVF 0x20, 0, 1    ; d=0 a=1: BSR bank 3, positive -> WREG
        \\      MOVLW 0xCC
        \\      MOVF 0x21, 1, 1    ; d=1 a=1: BSR bank 3, zero written back to f
        \\  END
    );
    defer pic.deinit();

    // Access bank data (addr < 0x60 → bank 0)
    pic.MEM[0x10] = 0x42;
    pic.MEM[0x11] = 0x00;
    pic.MEM[0x12] = 0x80;
    pic.MEM[0x13] = 0x22;
    // Bank 3 data
    pic.MEM[0x320] = 0x77; // bank 3, addr 0x20
    pic.MEM[0x321] = 0x00; // bank 3, addr 0x21

    // Case 1: d=0 a=0 — 0x42 -> WREG; f unchanged, Z=0 N=0
    try pic.execInstruction(); // MOVLW 0xFF (poison)
    try pic.execInstruction(); // MOVF 0x10, 0, 0
    try std.testing.expectEqual(0x42, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x42, pic.MEM[0x10]); // f must not be modified
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 2: d=1 a=0 — 0x00 written back to f; WREG sentinel 0xBB unchanged, Z=1 N=0
    try pic.execInstruction(); // MOVLW 0xBB (sentinel)
    try pic.execInstruction(); // MOVF 0x11, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x11]); // written back
    try std.testing.expectEqual(0xBB, pic.REGS.WREG.*); // WREG untouched
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 3: d=0 a=0 — 0x80 -> WREG; f unchanged, Z=0 N=1
    try pic.execInstruction(); // MOVLW 0x00 (poison)
    try pic.execInstruction(); // MOVF 0x12, 0, 0
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x80, pic.MEM[0x12]); // f must not be modified
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Case 4: d=1 a=0 — 0x22 written back to f; WREG sentinel 0xAA unchanged, Z=0 N=0
    try pic.execInstruction(); // MOVLW 0xAA (sentinel)
    try pic.execInstruction(); // MOVF 0x13, 1, 0
    try std.testing.expectEqual(0x22, pic.MEM[0x13]); // written back
    try std.testing.expectEqual(0xAA, pic.REGS.WREG.*); // WREG untouched
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 5: d=0 a=1 — BSR bank 3, addr 0x20: 0x77 -> WREG; f unchanged, Z=0 N=0
    try pic.execInstruction(); // MOVLB 3
    try std.testing.expectEqual(3, pic.REGS.BSR.*);
    try pic.execInstruction(); // MOVLW 0x00 (poison)
    try pic.execInstruction(); // MOVF 0x20, 0, 1
    try std.testing.expectEqual(0x77, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x77, pic.MEM[0x320]); // f must not be modified
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 6: d=1 a=1 — BSR bank 3, addr 0x21: 0x00 written back; WREG sentinel 0xCC unchanged, Z=1
    try pic.execInstruction(); // MOVLW 0xCC (sentinel)
    try pic.execInstruction(); // MOVF 0x21, 1, 1
    try std.testing.expectEqual(0x00, pic.MEM[0x321]); // written back
    try std.testing.expectEqual(0xCC, pic.REGS.WREG.*); // WREG untouched
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "ANDWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x0F
        \\      ANDWF 0x10, 0, 0   ; 0xAB & 0x0F = 0x0B -> WREG
        \\      MOVLW 0x0F
        \\      ANDWF 0x11, 1, 0   ; 0xF0 & 0x0F = 0x00 -> f, Z=1
        \\      MOVLW 0x80
        \\      ANDWF 0x12, 0, 0   ; 0xFF & 0x80 = 0x80 -> WREG, N=1
        \\      MOVLW 0x3C
        \\      ANDWF 0x13, 1, 0   ; 0x3C & 0x3C = 0x3C -> f
        \\      MOVLB 4
        \\      MOVLW 0xAA
        \\      ANDWF 0x20, 0, 1   ; 0xF5 & 0xAA = 0xA0 -> WREG, BSR bank 4, N=1
        \\      MOVLW 0x33
        \\      ANDWF 0x21, 1, 1   ; 0x55 & 0x33 = 0x11 -> f, BSR bank 4
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xAB;
    pic.MEM[0x11] = 0xF0;
    pic.MEM[0x12] = 0xFF;
    pic.MEM[0x13] = 0x3C;
    pic.MEM[0x420] = 0xF5;
    pic.MEM[0x421] = 0x55;

    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // ANDWF 0x10, 0, 0
    try std.testing.expectEqual(0x0B, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xAB, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // ANDWF 0x11, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(0x0F, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x80
    try pic.execInstruction(); // ANDWF 0x12, 0, 0
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xFF, pic.MEM[0x12]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x3C
    try pic.execInstruction(); // ANDWF 0x13, 1, 0
    try std.testing.expectEqual(0x3C, pic.MEM[0x13]);
    try std.testing.expectEqual(0x3C, pic.REGS.WREG.*); // WREG unchanged

    try pic.execInstruction(); // MOVLB 4
    try std.testing.expectEqual(4, pic.REGS.BSR.*);
    try pic.execInstruction(); // MOVLW 0xAA
    try pic.execInstruction(); // ANDWF 0x20, 0, 1
    try std.testing.expectEqual(0xA0, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xF5, pic.MEM[0x420]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x33
    try pic.execInstruction(); // ANDWF 0x21, 1, 1
    try std.testing.expectEqual(0x11, pic.MEM[0x421]);
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "IORLW instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x0F
        \\      IORLW 0xA0   ; 0x0F | 0xA0 = 0xAF -> WREG, N=1
        \\      MOVLW 0x00
        \\      IORLW 0x00   ; 0x00 | 0x00 = 0x00 -> WREG, Z=1
        \\      MOVLW 0x55
        \\      IORLW 0xAA   ; 0x55 | 0xAA = 0xFF -> WREG, N=1
        \\      MOVLW 0x0F
        \\      IORLW 0x30   ; 0x0F | 0x30 = 0x3F -> WREG, N=0 Z=0
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // IORLW 0xA0
    try std.testing.expectEqual(0xAF, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x00
    try pic.execInstruction(); // IORLW 0x00
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x55
    try pic.execInstruction(); // IORLW 0xAA
    try std.testing.expectEqual(0xFF, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // IORLW 0x30
    try std.testing.expectEqual(0x3F, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "IORWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x0F
        \\      IORWF 0x10, 0, 0   ; 0xA0 | 0x0F = 0xAF -> WREG, N=1
        \\      MOVLW 0x00
        \\      IORWF 0x11, 1, 0   ; 0x00 | 0x00 = 0x00 -> f, Z=1
        \\      MOVLW 0xF0
        \\      IORWF 0x12, 0, 0   ; 0x0F | 0xF0 = 0xFF -> WREG, N=1
        \\      MOVLW 0x11
        \\      IORWF 0x13, 1, 0   ; 0x22 | 0x11 = 0x33 -> f
        \\      MOVLB 3
        \\      MOVLW 0x0F
        \\      IORWF 0x20, 0, 1   ; 0x50 | 0x0F = 0x5F -> WREG, BSR bank 3
        \\      MOVLW 0x01
        \\      IORWF 0x21, 1, 1   ; 0x80 | 0x01 = 0x81 -> f, BSR bank 3, N=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xA0;
    pic.MEM[0x11] = 0x00;
    pic.MEM[0x12] = 0x0F;
    pic.MEM[0x13] = 0x22;
    pic.MEM[0x320] = 0x50;
    pic.MEM[0x321] = 0x80;

    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // IORWF 0x10, 0, 0
    try std.testing.expectEqual(0xAF, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xA0, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x00
    try pic.execInstruction(); // IORWF 0x11, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0xF0
    try pic.execInstruction(); // IORWF 0x12, 0, 0
    try std.testing.expectEqual(0xFF, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x0F, pic.MEM[0x12]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x11
    try pic.execInstruction(); // IORWF 0x13, 1, 0
    try std.testing.expectEqual(0x33, pic.MEM[0x13]);
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*); // WREG unchanged

    try pic.execInstruction(); // MOVLB 3
    try std.testing.expectEqual(3, pic.REGS.BSR.*);
    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // IORWF 0x20, 0, 1
    try std.testing.expectEqual(0x5F, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x50, pic.MEM[0x320]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // IORWF 0x21, 1, 1
    try std.testing.expectEqual(0x81, pic.MEM[0x321]);
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "ANDLW instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0xAF
        \\      ANDLW 0x0F   ; 0xAF & 0x0F = 0x0F -> WREG
        \\      MOVLW 0xF0
        \\      ANDLW 0x0F   ; 0xF0 & 0x0F = 0x00 -> WREG, Z=1
        \\      MOVLW 0xFF
        \\      ANDLW 0x80   ; 0xFF & 0x80 = 0x80 -> WREG, N=1
        \\      MOVLW 0x3C
        \\      ANDLW 0x3C   ; 0x3C & 0x3C = 0x3C -> WREG
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // MOVLW 0xAF
    try pic.execInstruction(); // ANDLW 0x0F
    try std.testing.expectEqual(0x0F, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0xF0
    try pic.execInstruction(); // ANDLW 0x0F
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0xFF
    try pic.execInstruction(); // ANDLW 0x80
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x3C
    try pic.execInstruction(); // ANDLW 0x3C
    try std.testing.expectEqual(0x3C, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
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

test "MOVLB instruction" {
    var pic = try asm2emu(
        \\      MOVLB 2
        \\      MOVLB 5
        \\  END
    );
    defer pic.deinit();

    // Doc example: before BSR=02h (set by first MOVLB), after BSR=05h
    try pic.execInstruction();
    try std.testing.expectEqual(0x02, pic.REGS.BSR.*);

    try pic.execInstruction();
    try std.testing.expectEqual(0x05, pic.REGS.BSR.*);

    // Status Affected: None
}

test "MOVFF instruction" {
    var pic = try asm2emu(
        \\      MOVFF 0x100, 0x200
        \\      MOVFF 0x100, POSTDEC0
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x100] = 0x33;
    pic.MEM[0x200] = 0x11;
    pic.REGS.FSR0H.* = 0x00;
    pic.REGS.FSR0L.* = 0x50;

    // Plain register-to-register copy
    try pic.execInstruction();
    try std.testing.expectEqual(0x33, pic.MEM[0x100]);
    try std.testing.expectEqual(0x33, pic.MEM[0x200]);

    // MOVFF to POSTDEC0: writes to MEM[FSR0]=MEM[0x50], then FSR0 decrements to 0x4F
    try pic.execInstruction();
    try std.testing.expectEqual(0x33, pic.MEM[0x50]);
    try std.testing.expectEqual(0x4F, pic.REGS.FSR0L.*);

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

test "RETLW instruction" {
    var pic = try asm2emu(
        \\      CALL entry0, 0
        \\      NOP
        \\      CALL entry1, 0
        \\      NOP
        \\      CALL entry2, 0
        \\      NOP
        \\entry0:
        \\      RETLW 0xAA
        \\entry1:
        \\      RETLW 0xBB
        \\entry2:
        \\      RETLW 0xCC
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // CALL entry0
    try pic.execInstruction(); // RETLW 0xAA
    try std.testing.expectEqual(0xAA, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x04, pic.PC); // returned to NOP after first CALL

    try pic.execInstruction(); // NOP
    try pic.execInstruction(); // CALL entry1
    try pic.execInstruction(); // RETLW 0xBB
    try std.testing.expectEqual(0xBB, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x0A, pic.PC); // returned to NOP after second CALL

    try pic.execInstruction(); // NOP
    try pic.execInstruction(); // CALL entry2
    try pic.execInstruction(); // RETLW 0xCC
    try std.testing.expectEqual(0xCC, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x10, pic.PC); // returned to NOP after third CALL

    // Status Affected: None
}

test "CALL and RETURN instruction" {
    var pic = try asm2emu(
        \\      CALL sub_a, 0
        \\      NOP
        \\sub_c:
        \\      MOVLW 0x33
        \\      RETURN
        \\sub_a:
        \\      MOVLW 0x11
        \\      CALL sub_b, 0
        \\      RETURN
        \\sub_b:
        \\      MOVLW 0x22
        \\      CALL sub_c, 0
        \\      RETURN
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // CALL sub_a
    try pic.execInstruction(); // MOVLW 0x11
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);

    try pic.execInstruction(); // CALL sub_b
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);

    try pic.execInstruction(); // CALL sub_c
    try pic.execInstruction(); // MOVLW 0x33
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*);

    try pic.execInstruction(); // RETURN from sub_c -> lands on sub_b's RETURN
    try pic.execInstruction(); // RETURN from sub_b -> lands on sub_a's RETURN
    try pic.execInstruction(); // RETURN from sub_a -> lands on NOP at 0x04

    try std.testing.expectEqual(0x33, pic.REGS.WREG.*); // unchanged through RETURNs
    try std.testing.expectEqual(0x04, pic.PC); // back in main after initial CALL

    // Status Affected: None
}
