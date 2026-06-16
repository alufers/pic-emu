const std = @import("std");
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

test "MULLW instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0xE2
        \\      MULLW 0xC4         ; doc example: 0xE2 * 0xC4 = 0xAD08
        \\      MOVLW 0x05
        \\      MULLW 0x03         ; 0x05 * 0x03 = 0x000F
        \\      MOVLW 0x00
        \\      MULLW 0xFF         ; 0x00 * 0xFF = 0x0000
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // MOVLW 0xE2
    try pic.execInstruction(); // MULLW 0xC4
    try std.testing.expectEqual(0xE2, pic.REGS.WREG.*); // W unchanged
    try std.testing.expectEqual(0xAD, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x08, pic.REGS.PRODL.*);

    try pic.execInstruction(); // MOVLW 0x05
    try pic.execInstruction(); // MULLW 0x03
    try std.testing.expectEqual(0x00, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x0F, pic.REGS.PRODL.*);

    try pic.execInstruction(); // MOVLW 0x00
    try pic.execInstruction(); // MULLW 0xFF
    try std.testing.expectEqual(0x00, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x00, pic.REGS.PRODL.*);

    // Status Affected: None
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

test "BTFSS instruction" {
    var pic = try asm2emu(
        \\      BTFSS 0x10, 3, 0   ; bit 3 of 0x08 = 1 -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x11         ; WREG = 0x11 (skip happened)
        \\      BTFSS 0x11, 3, 0   ; bit 3 of 0x00 = 0 -> no skip
        \\      MOVLW 0x22         ; WREG = 0x22 (no skip)
        \\      MOVLB 5
        \\      BTFSS 0x20, 7, 1   ; bit 7 of MEM[0x520]=0x80 = 1 -> skip, BSR bank 5
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x44         ; WREG = 0x44 (skip happened)
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x08; // bit 3 = 1 -> skip
    pic.MEM[0x11] = 0x00; // bit 3 = 0 -> no skip
    pic.MEM[0x520] = 0x80; // bit 7 = 1 -> skip

    try pic.execInstruction(); // BTFSS 0x10, 3 -> skip
    try pic.execInstruction(); // MOVLW 0x11
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);

    try pic.execInstruction(); // BTFSS 0x11, 3 -> no skip
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLB 5
    try pic.execInstruction(); // BTFSS 0x20, 7, 1 -> skip
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

test "ADDWFC instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x4D
        \\      ADDWFC 0x10, 0, 0   ; doc example: 0x4D + 0x02 + C=1 = 0x50 -> WREG, C=0
        \\      MOVLW 0x01
        \\      ADDWFC 0x11, 1, 0   ; 0xFE + 0x01 + C=0 = 0xFF -> f, N=1
        \\      MOVLW 0x01
        \\      ADDWFC 0x12, 1, 0   ; 0xFF + 0x01 + C=0 = 0x00 -> f, C=1, Z=1
        \\      MOVLW 0x70
        \\      ADDWFC 0x13, 1, 0   ; 0x70 + 0x10 + C=1 = 0x81 -> f, OV=1, N=1
        \\      MOVLB 2
        \\      MOVLW 0x08
        \\      ADDWFC 0x20, 0, 1   ; BSR bank 2: 0x08 + 0x08 + C=0 = 0x10 -> WREG, DC=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x02;
    pic.MEM[0x11] = 0xFE;
    pic.MEM[0x12] = 0xFF;
    pic.MEM[0x13] = 0x10;
    pic.MEM[0x220] = 0x08;

    pic.REGS.STATUS.*.C = 1;
    try pic.execInstruction(); // MOVLW 0x4D
    try pic.execInstruction(); // ADDWFC 0x10, 0, 0
    try std.testing.expectEqual(0x50, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x02, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // C=0 from previous: 0xFE + 0x01 + 0 = 0xFF
    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // ADDWFC 0x11, 1, 0
    try std.testing.expectEqual(0xFF, pic.MEM[0x11]);
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // C=0 from previous: 0xFF + 0x01 + 0 = 0x00, C=1, Z=1
    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // ADDWFC 0x12, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);

    // C=1 from previous: 0x10 + 0x70 + 1 = 0x81, OV=1, N=1
    try pic.execInstruction(); // MOVLW 0x70
    try pic.execInstruction(); // ADDWFC 0x13, 1, 0
    try std.testing.expectEqual(0x81, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);

    // C=0, BSR bank 2: 0x08 + 0x08 + 0 = 0x10 -> WREG, DC=1
    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // MOVLW 0x08
    try pic.execInstruction(); // ADDWFC 0x20, 0, 1
    try std.testing.expectEqual(0x10, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x08, pic.MEM[0x220]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);

    // Status Affected: C, DC, N, OV, Z
}

test "ADDWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x17
        \\      ADDWF 0x10, 0, 0   ; doc example: 0x17 + 0xC2 = 0xD9 -> WREG
        \\      MOVLW 0x01
        \\      ADDWF 0x11, 1, 0   ; 0xFF + 0x01 = 0x00 -> f, C=1, Z=1
        \\      MOVLW 0x70
        \\      ADDWF 0x12, 1, 0   ; 0x70 + 0x10 = 0x80 -> f, OV=1, N=1
        \\      MOVLW 0x08
        \\      ADDWF 0x13, 1, 0   ; 0x08 + 0x08 = 0x10 -> f, DC=1
        \\      MOVLB 7
        \\      MOVLW 0x22
        \\      ADDWF 0x20, 0, 1   ; BSR bank 7: 0x11 + 0x22 = 0x33 -> WREG
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xC2;
    pic.MEM[0x11] = 0xFF;
    pic.MEM[0x12] = 0x10;
    pic.MEM[0x13] = 0x08;
    pic.MEM[0x720] = 0x11;

    try pic.execInstruction(); // MOVLW 0x17
    try pic.execInstruction(); // ADDWF 0x10, 0, 0
    try std.testing.expectEqual(0xD9, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xC2, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // ADDWF 0x11, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);

    try pic.execInstruction(); // MOVLW 0x70
    try pic.execInstruction(); // ADDWF 0x12, 1, 0
    try std.testing.expectEqual(0x80, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);

    try pic.execInstruction(); // MOVLW 0x08
    try pic.execInstruction(); // ADDWF 0x13, 1, 0
    try std.testing.expectEqual(0x10, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);

    try pic.execInstruction(); // MOVLB 7
    try pic.execInstruction(); // MOVLW 0x22
    try pic.execInstruction(); // ADDWF 0x20, 0, 1
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x11, pic.MEM[0x720]); // f unchanged

    // Status Affected: C, DC, N, OV, Z
}

test "SUBWFB instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x0D
        \\      SUBWFB 0x10, 1, 0  ; ex1: 0x19 - 0x0D - borrow(C=1)=0 = 0x0C -> f, C=1
        \\      MOVLW 0x1A
        \\      SUBWFB 0x11, 0, 0  ; 0x1B - 0x1A - borrow(C=1)=0 = 0x01 -> WREG, C=1
        \\      MOVLW 0x0E
        \\      SUBWFB 0x12, 1, 0  ; ex3: 0x03 - 0x0E - borrow(C=1)=0 = 0xF5 -> f, C=0, N=1
        \\      MOVLB 4
        \\      MOVLW 0x02
        \\      SUBWFB 0x20, 0, 1  ; BSR bank 4: 0x05 - 0x02 - borrow(C=0)=1 = 0x02 -> WREG
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x19;
    pic.MEM[0x11] = 0x1B;
    pic.MEM[0x12] = 0x03;
    pic.MEM[0x420] = 0x05;

    // Example 1: 0x19 - 0x0D - 0 = 0x0C, C=1
    pic.REGS.STATUS.*.C = 1;
    try pic.execInstruction(); // MOVLW 0x0D
    try pic.execInstruction(); // SUBWFB 0x10, 1, 0
    try std.testing.expectEqual(0x0C, pic.MEM[0x10]);
    try std.testing.expectEqual(0x0D, pic.REGS.WREG.*); // W unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Example 2 (adapted): C=1 from prev -> 0x1B - 0x1A - 0 = 0x01 -> WREG, C=1
    try pic.execInstruction(); // MOVLW 0x1A
    try pic.execInstruction(); // SUBWFB 0x11, 0, 0
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x1B, pic.MEM[0x11]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // Example 3: C=1 from prev -> 0x03 - 0x0E - 0 = 0xF5, C=0, N=1
    try pic.execInstruction(); // MOVLW 0x0E
    try pic.execInstruction(); // SUBWFB 0x12, 1, 0
    try std.testing.expectEqual(0xF5, pic.MEM[0x12]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // BSR bank 4: C=0 -> borrow=1; 0x05 - 0x02 - 1 = 0x02, C=1
    try pic.execInstruction(); // MOVLB 4
    try pic.execInstruction(); // MOVLW 0x02
    try pic.execInstruction(); // SUBWFB 0x20, 0, 1
    try std.testing.expectEqual(0x02, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x05, pic.MEM[0x420]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);

    // Status Affected: C, DC, N, OV, Z
}

test "SUBWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0x02
        \\      SUBWF 0x10, 1, 0   ; doc example: 0x03 - 0x02 = 0x01 -> f, C=1 Z=0 N=0
        \\      MOVLW 0x05
        \\      SUBWF 0x11, 0, 0   ; 0x05 - 0x05 = 0x00 -> WREG, Z=1
        \\      MOVLW 0x04
        \\      SUBWF 0x12, 1, 0   ; 0x02 - 0x04 = 0xFE -> f, C=0 (borrow), N=1
        \\      MOVLW 0x01
        \\      SUBWF 0x13, 1, 0   ; 0x80 - 0x01 = 0x7F -> f, OV=1 (neg-pos=pos)
        \\      MOVLB 3
        \\      MOVLW 0x10
        \\      SUBWF 0x20, 0, 1   ; BSR bank 3: 0x20 - 0x10 = 0x10 -> WREG
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x03;
    pic.MEM[0x11] = 0x05;
    pic.MEM[0x12] = 0x02;
    pic.MEM[0x13] = 0x80;
    pic.MEM[0x320] = 0x20;

    try pic.execInstruction(); // MOVLW 0x02
    try pic.execInstruction(); // SUBWF 0x10, 1, 0
    try std.testing.expectEqual(0x01, pic.MEM[0x10]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    try pic.execInstruction(); // MOVLW 0x05
    try pic.execInstruction(); // SUBWF 0x11, 0, 0
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x05, pic.MEM[0x11]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);

    try pic.execInstruction(); // MOVLW 0x04
    try pic.execInstruction(); // SUBWF 0x12, 1, 0
    try std.testing.expectEqual(0xFE, pic.MEM[0x12]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // borrow

    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // SUBWF 0x13, 1, 0
    try std.testing.expectEqual(0x7F, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);

    try pic.execInstruction(); // MOVLB 3
    try pic.execInstruction(); // MOVLW 0x10
    try pic.execInstruction(); // SUBWF 0x20, 0, 1
    try std.testing.expectEqual(0x10, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x20, pic.MEM[0x320]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);

    // Status Affected: C, DC, N, OV, Z
}

test "INCF instruction" {
    var pic = try asm2emu(
        \\      INCF 0x10, 1, 0    ; 0x01 -> 0x02 -> f
        \\      INCF 0x11, 0, 0    ; 0x7E -> 0x7F -> WREG, f unchanged
        \\      INCF 0x12, 1, 0    ; 0x7F -> 0x80: OV=1, N=1
        \\      INCF 0x13, 1, 0    ; doc example: 0xFF -> 0x00: Z=1, C=1, DC=1
        \\      MOVLB 5
        \\      INCF 0x20, 0, 1    ; BSR bank 5: 0x0F -> 0x10 -> WREG, DC=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x01;
    pic.MEM[0x11] = 0x7E;
    pic.MEM[0x12] = 0x7F;
    pic.MEM[0x13] = 0xFF;
    pic.MEM[0x520] = 0x0F;

    try pic.execInstruction(); // INCF 0x10, 1, 0
    try std.testing.expectEqual(0x02, pic.MEM[0x10]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    try pic.execInstruction(); // INCF 0x11, 0, 0
    try std.testing.expectEqual(0x7F, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x7E, pic.MEM[0x11]); // f unchanged

    try pic.execInstruction(); // INCF 0x12, 1, 0
    try std.testing.expectEqual(0x80, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);

    try pic.execInstruction(); // INCF 0x13, 1, 0  (doc example)
    try std.testing.expectEqual(0x00, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLB 5
    try pic.execInstruction(); // INCF 0x20, 0, 1
    try std.testing.expectEqual(0x10, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x0F, pic.MEM[0x520]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);

    // Status Affected: C, DC, N, OV, Z
}

test "DECFSZ instruction" {
    var pic = try asm2emu(
        \\      DECFSZ 0x10, 1, 0  ; 0x02 -> 0x01, no skip
        \\      MOVLW 0x11         ; WREG = 0x11 (no skip)
        \\      DECFSZ 0x10, 1, 0  ; 0x01 -> 0x00, skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x22         ; WREG = 0x22 (skip happened)
        \\      DECFSZ 0x11, 0, 0  ; d=0: result to WREG, f unchanged; 0x01 -> 0x00, skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x33         ; WREG = 0x33
        \\      MOVLB 4
        \\      DECFSZ 0x20, 1, 1  ; BSR bank 4: 0x01 -> 0x00, skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x44         ; WREG = 0x44
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x02;
    pic.MEM[0x11] = 0x01;
    pic.MEM[0x420] = 0x01;

    try pic.execInstruction(); // DECFSZ 0x10 (0x02->0x01, no skip)
    try std.testing.expectEqual(0x01, pic.MEM[0x10]);
    try pic.execInstruction(); // MOVLW 0x11 (not skipped)
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);

    try pic.execInstruction(); // DECFSZ 0x10 (0x01->0x00, skip)
    try pic.execInstruction(); // MOVLW 0x22 (trap skipped)
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x00, pic.MEM[0x10]);

    try pic.execInstruction(); // DECFSZ 0x11, 0 (d=0: WREG=0x00, f unchanged, skip)
    try pic.execInstruction(); // MOVLW 0x33
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x01, pic.MEM[0x11]); // f unchanged

    try pic.execInstruction(); // MOVLB 4
    try pic.execInstruction(); // DECFSZ 0x20, 1, 1 (BSR bank 4, skip)
    try pic.execInstruction(); // MOVLW 0x44
    try std.testing.expectEqual(0x44, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x00, pic.MEM[0x420]);

    // Status Affected: None
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

test "BZ instruction - branch taken (Z=1)" {
    var pic = try asm2emu(
        \\      BZ skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.Z = 1;
    try pic.execInstruction();

    try std.testing.expectEqual(6, pic.PC);

    // Status Affected: None
}

test "BZ instruction - branch not taken (Z=0)" {
    var pic = try asm2emu(
        \\      BZ skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.Z = 0;
    try pic.execInstruction();

    try std.testing.expectEqual(2, pic.PC);

    // Status Affected: None
}

test "BC instruction - branch taken (C=1)" {
    var pic = try asm2emu(
        \\      BC skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.C = 1;
    try pic.execInstruction();

    try std.testing.expectEqual(6, pic.PC);

    // Status Affected: None
}

test "BC instruction - branch not taken (C=0)" {
    var pic = try asm2emu(
        \\      BC skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.C = 0;
    try pic.execInstruction();

    try std.testing.expectEqual(2, pic.PC);

    // Status Affected: None
}

test "BNC instruction - branch taken (C=0)" {
    var pic = try asm2emu(
        \\      BNC skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.C = 0;
    try pic.execInstruction();

    try std.testing.expectEqual(6, pic.PC);

    // Status Affected: None
}

test "BNC instruction - branch not taken (C=1)" {
    var pic = try asm2emu(
        \\      BNC skip
        \\      NOP
        \\      NOP
        \\skip
        \\      NOP
        \\  END
    );
    defer pic.deinit();
    pic.REGS.STATUS.*.C = 1;
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

test "RRCF instruction" {
    var pic = try asm2emu(
        \\      RRCF 0x10, 0, 0    ; doc example: 0xE6, C=0 -> W=0x73, C=0
        \\      RRCF 0x11, 1, 0    ; 0x01, C=0 -> f=0x00, C=1, Z=1
        \\      RRCF 0x12, 0, 0    ; 0x00, C=1 -> W=0x80, C=0, N=1
        \\      RRCF 0x13, 1, 0    ; 0xFE, C=0 -> f=0x7F, C=0
        \\      MOVLB 4
        \\      RRCF 0x20, 0, 1    ; BSR bank 4: 0xAA, C=0 -> W=0x55, C=0
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xE6;
    pic.MEM[0x11] = 0x01;
    pic.MEM[0x12] = 0x00;
    pic.MEM[0x13] = 0xFE;
    pic.MEM[0x420] = 0xAA;

    pic.REGS.STATUS.*.C = 0;
    try pic.execInstruction(); // RRCF 0x10, 0, 0
    try std.testing.expectEqual(0x73, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xE6, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // C=0 from previous
    try pic.execInstruction(); // RRCF 0x11, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // C=1 from previous
    try pic.execInstruction(); // RRCF 0x12, 0, 0
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x00, pic.MEM[0x12]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // C=0 from previous
    try pic.execInstruction(); // RRCF 0x13, 1, 0
    try std.testing.expectEqual(0x7F, pic.MEM[0x13]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // C=0, BSR bank 4
    try pic.execInstruction(); // MOVLB 4
    try pic.execInstruction(); // RRCF 0x20, 0, 1
    try std.testing.expectEqual(0x55, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xAA, pic.MEM[0x420]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Status Affected: C, N, Z
}

test "RLNCF instruction" {
    var pic = try asm2emu(
        \\      RLNCF 0x10, 1, 0   ; doc example: 0xAB -> 0x57 -> f
        \\      RLNCF 0x11, 0, 0   ; 0x80 -> 0x01 -> WREG, f unchanged
        \\      RLNCF 0x12, 1, 0   ; 0x40 -> 0x80 -> f, N=1
        \\      RLNCF 0x13, 1, 0   ; 0x00 -> 0x00 -> f, Z=1
        \\      MOVLB 2
        \\      RLNCF 0x20, 0, 1   ; BSR bank 2: 0xC0 -> 0x81 -> WREG, N=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xAB;
    pic.MEM[0x11] = 0x80;
    pic.MEM[0x12] = 0x40;
    pic.MEM[0x13] = 0x00;
    pic.MEM[0x220] = 0xC0;

    try pic.execInstruction(); // RLNCF 0x10, 1, 0
    try std.testing.expectEqual(0x57, pic.MEM[0x10]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // RLNCF 0x11, 0, 0
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x80, pic.MEM[0x11]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // RLNCF 0x12, 1, 0
    try std.testing.expectEqual(0x80, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    try pic.execInstruction(); // RLNCF 0x13, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);

    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // RLNCF 0x20, 0, 1
    try std.testing.expectEqual(0x81, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xC0, pic.MEM[0x220]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "SWAPF instruction" {
    var pic = try asm2emu(
        \\      SWAPF 0x10, 1, 0   ; doc example: 0x53 -> 0x35 -> f
        \\      SWAPF 0x11, 0, 0   ; 0xAB -> 0xBA -> WREG, f unchanged
        \\      SWAPF 0x12, 1, 0   ; 0xF0 -> 0x0F -> f
        \\      MOVLB 3
        \\      SWAPF 0x20, 0, 1   ; BSR bank 3: 0x12 -> 0x21 -> WREG
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x53;
    pic.MEM[0x11] = 0xAB;
    pic.MEM[0x12] = 0xF0;
    pic.MEM[0x320] = 0x12;

    try pic.execInstruction(); // SWAPF 0x10, 1, 0
    try std.testing.expectEqual(0x35, pic.MEM[0x10]);

    try pic.execInstruction(); // SWAPF 0x11, 0, 0
    try std.testing.expectEqual(0xBA, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xAB, pic.MEM[0x11]); // f unchanged

    try pic.execInstruction(); // SWAPF 0x12, 1, 0
    try std.testing.expectEqual(0x0F, pic.MEM[0x12]);

    try pic.execInstruction(); // MOVLB 3
    try pic.execInstruction(); // SWAPF 0x20, 0, 1
    try std.testing.expectEqual(0x21, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x12, pic.MEM[0x320]); // f unchanged

    // Status Affected: None
}

test "RLCF instruction" {
    var pic = try asm2emu(
        \\      RLCF 0x10, 0, 0    ; doc example: 0xE6, C=0 -> W=0xCC, C=1
        \\      RLCF 0x11, 1, 0    ; 0x01, C=1 -> f=0x03, C=0
        \\      RLCF 0x12, 0, 0    ; 0x7F, C=0 -> W=0xFE, C=0, N=1
        \\      RLCF 0x13, 1, 0    ; 0x80, C=0 -> f=0x00, C=1, Z=1
        \\      MOVLB 2
        \\      RLCF 0x20, 0, 1    ; BSR bank 2: 0x55, C=1 -> W=0xAB, C=0
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xE6;
    pic.MEM[0x11] = 0x01;
    pic.MEM[0x12] = 0x7F;
    pic.MEM[0x13] = 0x80;
    pic.MEM[0x220] = 0x55;

    pic.REGS.STATUS.*.C = 0;
    try pic.execInstruction(); // RLCF 0x10, 0, 0
    try std.testing.expectEqual(0xCC, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xE6, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // C=1 from previous
    try pic.execInstruction(); // RLCF 0x11, 1, 0
    try std.testing.expectEqual(0x03, pic.MEM[0x11]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // C=0 from previous
    try pic.execInstruction(); // RLCF 0x12, 0, 0
    try std.testing.expectEqual(0xFE, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x7F, pic.MEM[0x12]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // C=0 from previous
    try pic.execInstruction(); // RLCF 0x13, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // C=1 from previous, BSR bank 2
    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // RLCF 0x20, 0, 1
    try std.testing.expectEqual(0xAB, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x55, pic.MEM[0x220]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Status Affected: C, N, Z
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

test "XORWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0xFF
        \\      XORWF 0x10, 0, 0   ; 0xAA ^ 0xFF = 0x55 -> WREG
        \\      MOVLW 0xAA
        \\      XORWF 0x11, 1, 0   ; 0xAA ^ 0xAA = 0x00 -> f, Z=1
        \\      MOVLW 0x0F
        \\      XORWF 0x12, 0, 0   ; 0x7F ^ 0x0F = 0x70 -> WREG
        \\      MOVLW 0x01
        \\      XORWF 0x13, 1, 0   ; 0x80 ^ 0x01 = 0x81 -> f, N=1
        \\      MOVLB 6
        \\      MOVLW 0xF0
        \\      XORWF 0x20, 0, 1   ; 0x3C ^ 0xF0 = 0xCC -> WREG, BSR bank 6, N=1
        \\      MOVLW 0x55
        \\      XORWF 0x21, 1, 1   ; 0x55 ^ 0x55 = 0x00 -> f, BSR bank 6, Z=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xAA;
    pic.MEM[0x11] = 0xAA;
    pic.MEM[0x12] = 0x7F;
    pic.MEM[0x13] = 0x80;
    pic.MEM[0x620] = 0x3C;
    pic.MEM[0x621] = 0x55;

    try pic.execInstruction(); // MOVLW 0xFF
    try pic.execInstruction(); // XORWF 0x10, 0, 0
    try std.testing.expectEqual(0x55, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xAA, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0xAA
    try pic.execInstruction(); // XORWF 0x11, 1, 0
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(0xAA, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x0F
    try pic.execInstruction(); // XORWF 0x12, 0, 0
    try std.testing.expectEqual(0x70, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x7F, pic.MEM[0x12]); // f unchanged

    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // XORWF 0x13, 1, 0
    try std.testing.expectEqual(0x81, pic.MEM[0x13]);
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLB 6
    try std.testing.expectEqual(6, pic.REGS.BSR.*);
    try pic.execInstruction(); // MOVLW 0xF0
    try pic.execInstruction(); // XORWF 0x20, 0, 1
    try std.testing.expectEqual(0xCC, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x3C, pic.MEM[0x620]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x55
    try pic.execInstruction(); // XORWF 0x21, 1, 1
    try std.testing.expectEqual(0x00, pic.MEM[0x621]);
    try std.testing.expectEqual(0x55, pic.REGS.WREG.*); // WREG unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

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

test "XORLW instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0xB5
        \\      XORLW 0xAF         ; doc example: 0xB5 ^ 0xAF = 0x1A, N=0 Z=0
        \\      MOVLW 0xFF
        \\      XORLW 0xFF         ; 0xFF ^ 0xFF = 0x00, Z=1 N=0
        \\      MOVLW 0x00
        \\      XORLW 0x80         ; 0x00 ^ 0x80 = 0x80, N=1 Z=0
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction(); // MOVLW 0xB5
    try pic.execInstruction(); // XORLW 0xAF
    try std.testing.expectEqual(0x1A, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0xFF
    try pic.execInstruction(); // XORLW 0xFF
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    try pic.execInstruction(); // MOVLW 0x00
    try pic.execInstruction(); // XORLW 0x80
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Status Affected: N, Z
}

test "ADDLW instruction" {
    // ADDLW: (W) + k -> W. Status Affected: N, OV, C, DC, Z
    // Carry convention for addition: C=1 means a carry out of bit 7 (unsigned overflow).
    // DC=1 means a carry out of bit 3. OV=1 means signed overflow.
    var pic = try asm2emu(
        \\      MOVLW 0x10
        \\      ADDLW 0x15         ; doc example: 0x10 + 0x15 = 0x25, all flags clear
        \\      MOVLW 0xFF
        \\      ADDLW 0x01         ; 0xFF + 0x01 = 0x00: C=1, DC=1, Z=1
        \\      MOVLW 0x50
        \\      ADDLW 0xC0         ; 0x50 + 0xC0 = 0x110 -> 0x10: C=1, no DC, no OV
        \\      MOVLW 0x08
        \\      ADDLW 0x08         ; 0x08 + 0x08 = 0x10: DC=1, C=0
        \\      MOVLW 0x40
        \\      ADDLW 0x40         ; 0x40 + 0x40 = 0x80: OV=1, N=1, C=0
        \\  END
    );
    defer pic.deinit();

    // Case 1 (doc): 0x10 + 0x15 = 0x25, no carries, positive, nonzero
    try pic.execInstruction(); // MOVLW 0x10
    try pic.execInstruction(); // ADDLW 0x15
    try std.testing.expectEqual(0x25, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // Case 2: 0xFF + 0x01 = 0x00, full carry and digit carry, zero result
    try pic.execInstruction(); // MOVLW 0xFF
    try pic.execInstruction(); // ADDLW 0x01
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // Case 3: 0x50 + 0xC0 = 0x110 -> 0x10, carry out of bit 7, no digit carry, no signed overflow
    try pic.execInstruction(); // MOVLW 0x50
    try pic.execInstruction(); // ADDLW 0xC0
    try std.testing.expectEqual(0x10, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV); // pos + neg can never signed-overflow

    // Case 4: 0x08 + 0x08 = 0x10, only digit carry (bit 3 -> bit 4)
    try pic.execInstruction(); // MOVLW 0x08
    try pic.execInstruction(); // ADDLW 0x08
    try std.testing.expectEqual(0x10, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // Case 5: 0x40 + 0x40 = 0x80, signed overflow (pos + pos = neg)
    try pic.execInstruction(); // MOVLW 0x40
    try pic.execInstruction(); // ADDLW 0x40
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV);

    // Status Affected: N, OV, C, DC, Z
}

test "MULWF instruction" {
    var pic = try asm2emu(
        \\      MOVLW 0xC4
        \\      MULWF 0x10, 0      ; doc example: 0xC4 * 0xB5 = 0x8A94
        \\      MOVLW 0x05
        \\      MULWF 0x11, 0      ; 0x05 * 0x03 = 0x000F
        \\      MOVLW 0x00
        \\      MULWF 0x12, 0      ; 0x00 * 0xFF = 0x0000
        \\      MOVLB 6
        \\      MOVLW 0x10
        \\      MULWF 0x20, 1      ; BSR bank 6: 0x10 * 0x10 = 0x0100
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xB5;
    pic.MEM[0x11] = 0x03;
    pic.MEM[0x12] = 0xFF;
    pic.MEM[0x620] = 0x10;

    try pic.execInstruction(); // MOVLW 0xC4
    try pic.execInstruction(); // MULWF 0x10, 0
    try std.testing.expectEqual(0xC4, pic.REGS.WREG.*); // W unchanged
    try std.testing.expectEqual(0xB5, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0x8A, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x94, pic.REGS.PRODL.*);

    try pic.execInstruction(); // MOVLW 0x05
    try pic.execInstruction(); // MULWF 0x11, 0
    try std.testing.expectEqual(0x00, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x0F, pic.REGS.PRODL.*);

    try pic.execInstruction(); // MOVLW 0x00
    try pic.execInstruction(); // MULWF 0x12, 0
    try std.testing.expectEqual(0x00, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x00, pic.REGS.PRODL.*);

    try pic.execInstruction(); // MOVLB 6
    try pic.execInstruction(); // MOVLW 0x10
    try pic.execInstruction(); // MULWF 0x20, 1
    try std.testing.expectEqual(0x01, pic.REGS.PRODH.*);
    try std.testing.expectEqual(0x00, pic.REGS.PRODL.*);
    try std.testing.expectEqual(0x10, pic.MEM[0x620]); // f unchanged

    // Status Affected: None
}

test "INFSNZ instruction" {
    var pic = try asm2emu(
        \\      INFSNZ 0x10, 1, 0  ; 0x01 -> 0x02, nonzero -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x11         ; WREG = 0x11 (skip happened)
        \\      INFSNZ 0x11, 1, 0  ; 0xFF -> 0x00, zero -> no skip
        \\      MOVLW 0x22         ; WREG = 0x22 (no skip)
        \\      INFSNZ 0x12, 0, 0  ; d=0: result to W, f unchanged; 0x7E -> 0x7F nonzero -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x33         ; WREG = 0x33
        \\      MOVLB 4
        \\      INFSNZ 0x20, 1, 1  ; BSR bank 4: 0x05 -> 0x06 nonzero -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x44         ; WREG = 0x44
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x01;
    pic.MEM[0x11] = 0xFF;
    pic.MEM[0x12] = 0x7E;
    pic.MEM[0x420] = 0x05;

    try pic.execInstruction(); // INFSNZ 0x10 (0x01->0x02, nonzero, skip)
    try std.testing.expectEqual(0x02, pic.MEM[0x10]);
    try pic.execInstruction(); // MOVLW 0x11 (trap skipped)
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);

    try pic.execInstruction(); // INFSNZ 0x11 (0xFF->0x00, zero, no skip)
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try pic.execInstruction(); // MOVLW 0x22 (not skipped)
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);

    try pic.execInstruction(); // INFSNZ 0x12, 0 (d=0: W=0x7F, f unchanged, nonzero, skip)
    try std.testing.expectEqual(0x7F, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x7E, pic.MEM[0x12]); // f unchanged
    try pic.execInstruction(); // MOVLW 0x33 (trap skipped)
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLB 4
    try pic.execInstruction(); // INFSNZ 0x20, 1, 1 (BSR bank 4, 0x05->0x06, skip)
    try std.testing.expectEqual(0x06, pic.MEM[0x420]);
    try pic.execInstruction(); // MOVLW 0x44 (trap skipped)
    try std.testing.expectEqual(0x44, pic.REGS.WREG.*);

    // Status Affected: None
}

test "CPFSLT instruction" {
    // Compare f with W (unsigned), skip next instruction if f < W. f is not modified.
    var pic = try asm2emu(
        \\      MOVLW 0x50
        \\      CPFSLT 0x10, 0     ; f=0x30 < W=0x50 -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x11         ; WREG = 0x11 (skip happened)
        \\      MOVLW 0x20
        \\      CPFSLT 0x11, 0     ; f=0x50 > W=0x20 -> no skip
        \\      MOVLW 0x22         ; WREG = 0x22 (no skip)
        \\      MOVLW 0x40
        \\      CPFSLT 0x12, 0     ; f=0x40 == W=0x40 -> no skip (equal is not less)
        \\      MOVLW 0x33         ; WREG = 0x33 (no skip)
        \\      MOVLB 2
        \\      MOVLW 0xF0
        \\      CPFSLT 0x20, 1     ; BSR bank 2: f=0x10 < W=0xF0 -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x44         ; WREG = 0x44 (skip happened)
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x30;
    pic.MEM[0x11] = 0x50;
    pic.MEM[0x12] = 0x40;
    pic.MEM[0x220] = 0x10;

    try pic.execInstruction(); // MOVLW 0x50
    try pic.execInstruction(); // CPFSLT 0x10 -> skip
    try pic.execInstruction(); // MOVLW 0x11 (trap skipped)
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x30, pic.MEM[0x10]); // f unchanged

    try pic.execInstruction(); // MOVLW 0x20
    try pic.execInstruction(); // CPFSLT 0x11 -> no skip (f > W)
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLW 0x40
    try pic.execInstruction(); // CPFSLT 0x12 -> no skip (f == W)
    try pic.execInstruction(); // MOVLW 0x33
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // MOVLW 0xF0
    try pic.execInstruction(); // CPFSLT 0x20, 1 -> skip
    try pic.execInstruction(); // MOVLW 0x44 (trap skipped)
    try std.testing.expectEqual(0x44, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x10, pic.MEM[0x220]); // f unchanged

    // Status Affected: None
}

test "CPFSGT instruction" {
    // Compare f with W (unsigned), skip next instruction if f > W. f is not modified.
    var pic = try asm2emu(
        \\      MOVLW 0x20
        \\      CPFSGT 0x10, 0     ; f=0x50 > W=0x20 -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x11         ; WREG = 0x11 (skip happened)
        \\      MOVLW 0x80
        \\      CPFSGT 0x11, 0     ; f=0x30 < W=0x80 -> no skip
        \\      MOVLW 0x22         ; WREG = 0x22 (no skip)
        \\      MOVLW 0x40
        \\      CPFSGT 0x12, 0     ; f=0x40 == W=0x40 -> no skip (equal is not greater)
        \\      MOVLW 0x33         ; WREG = 0x33 (no skip)
        \\      MOVLB 3
        \\      MOVLW 0x05
        \\      CPFSGT 0x20, 1     ; BSR bank 3: f=0xF0 > W=0x05 -> skip
        \\      MOVLW 0xFF         ; trap
        \\      MOVLW 0x44         ; WREG = 0x44 (skip happened)
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x50;
    pic.MEM[0x11] = 0x30;
    pic.MEM[0x12] = 0x40;
    pic.MEM[0x320] = 0xF0;

    try pic.execInstruction(); // MOVLW 0x20
    try pic.execInstruction(); // CPFSGT 0x10 -> skip
    try pic.execInstruction(); // MOVLW 0x11 (trap skipped)
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x50, pic.MEM[0x10]); // f unchanged

    try pic.execInstruction(); // MOVLW 0x80
    try pic.execInstruction(); // CPFSGT 0x11 -> no skip (f < W)
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLW 0x40
    try pic.execInstruction(); // CPFSGT 0x12 -> no skip (f == W)
    try pic.execInstruction(); // MOVLW 0x33
    try std.testing.expectEqual(0x33, pic.REGS.WREG.*);

    try pic.execInstruction(); // MOVLB 3
    try pic.execInstruction(); // MOVLW 0x05
    try pic.execInstruction(); // CPFSGT 0x20, 1 -> skip
    try pic.execInstruction(); // MOVLW 0x44 (trap skipped)
    try std.testing.expectEqual(0x44, pic.REGS.WREG.*);
    try std.testing.expectEqual(0xF0, pic.MEM[0x320]); // f unchanged

    // Status Affected: None
}

test "SUBLW instruction" {
    // SUBLW: k - (W) -> W. Status Affected: N, OV, C, DC, Z
    // PIC subtraction carry convention: C=1 means no borrow (k >= W).
    var pic = try asm2emu(
        \\      MOVLW 0x01
        \\      SUBLW 0x02         ; doc example: 0x02 - 0x01 = 0x01, C=1, Z=0, N=0
        \\      MOVLW 0x02
        \\      SUBLW 0x02         ; 0x02 - 0x02 = 0x00, Z=1, C=1
        \\      MOVLW 0x03
        \\      SUBLW 0x02         ; 0x02 - 0x03 = 0xFF, borrow C=0, N=1
        \\      MOVLW 0x01
        \\      SUBLW 0x80         ; 0x80 - 0x01 = 0x7F, signed OV=1, C=1, N=0
        \\  END
    );
    defer pic.deinit();

    // Case 1: doc example W=0x01, k=0x02 -> 0x01
    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // SUBLW 0x02
    try std.testing.expectEqual(0x01, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow (2 >= 1)
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // no digit borrow

    // Case 2: W=0x02, k=0x02 -> 0x00, Z=1
    try pic.execInstruction(); // MOVLW 0x02
    try pic.execInstruction(); // SUBLW 0x02
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // Case 3: W=0x03, k=0x02 -> 0xFF, borrow C=0, N=1
    try pic.execInstruction(); // MOVLW 0x03
    try pic.execInstruction(); // SUBLW 0x02
    try std.testing.expectEqual(0xFF, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // borrow (2 < 3)
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // digit borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV); // same sign operands

    // Case 4: W=0x01, k=0x80 -> 0x7F, signed overflow OV=1
    try pic.execInstruction(); // MOVLW 0x01
    try pic.execInstruction(); // SUBLW 0x80
    try std.testing.expectEqual(0x7F, pic.REGS.WREG.*);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV); // -128 - 1 overflows
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow (0x80 >= 0x01)
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // digit borrow (0 - 1)

    // Status Affected: N, OV, C, DC, Z
}

test "COMF instruction" {
    // COMF: ~(f) -> dest. Status Affected: N, Z
    var pic = try asm2emu(
        \\      COMF 0x10, 0, 0    ; doc example: ~0x13 = 0xEC -> W, f unchanged
        \\      COMF 0x11, 1, 0    ; ~0xFF = 0x00 -> f, Z=1
        \\      COMF 0x12, 1, 0    ; ~0x00 = 0xFF -> f, N=1
        \\      MOVLB 4
        \\      COMF 0x20, 1, 1    ; BSR bank 4: ~0x0F = 0xF0 -> f, N=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x13;
    pic.MEM[0x11] = 0xFF;
    pic.MEM[0x12] = 0x00;
    pic.MEM[0x420] = 0x0F;

    // Case 1: d=0, ~0x13 = 0xEC -> W, f stays 0x13
    try pic.execInstruction();
    try std.testing.expectEqual(0xEC, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x13, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // Case 2: d=1, ~0xFF = 0x00 -> f, Z=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 3: d=1, ~0x00 = 0xFF -> f, N=1
    try pic.execInstruction();
    try std.testing.expectEqual(0xFF, pic.MEM[0x12]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);

    // Case 4: BSR bank 4, ~0x0F = 0xF0 -> f, N=1
    try pic.execInstruction(); // MOVLB 4
    try pic.execInstruction(); // COMF 0x20, 1, 1
    try std.testing.expectEqual(0xF0, pic.MEM[0x420]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // Status Affected: N, Z
}

test "RRNCF instruction" {
    // RRNCF: rotate right (no carry). f<n> -> dest<n-1>; f<0> -> dest<7>.
    // Status Affected: N, Z
    var pic = try asm2emu(
        \\      RRNCF 0x10, 1, 0   ; doc example: 0xD7 -> 0xEB
        \\      RRNCF 0x11, 0, 0   ; 0x01 -> 0x80 to W, f unchanged, N=1
        \\      RRNCF 0x12, 1, 0   ; 0x00 -> 0x00, Z=1
        \\      RRNCF 0x13, 1, 0   ; 0x02 -> 0x01, N=0, Z=0
        \\      MOVLB 1
        \\      RRNCF 0x20, 1, 1   ; BSR bank 1: 0xAA -> 0x55
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0xD7;
    pic.MEM[0x11] = 0x01;
    pic.MEM[0x12] = 0x00;
    pic.MEM[0x13] = 0x02;
    pic.MEM[0x120] = 0xAA;

    // Case 1: doc example 0xD7 -> 0xEB
    try pic.execInstruction();
    try std.testing.expectEqual(0xEB, pic.MEM[0x10]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // Case 2: d=0, 0x01 -> 0x80 to W, f unchanged, N=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x80, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x01, pic.MEM[0x11]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // Case 3: 0x00 -> 0x00, Z=1
    try pic.execInstruction();
    try std.testing.expectEqual(0x00, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 4: 0x02 -> 0x01
    try pic.execInstruction();
    try std.testing.expectEqual(0x01, pic.MEM[0x13]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);

    // Case 5: BSR bank 1, 0xAA -> 0x55
    try pic.execInstruction(); // MOVLB 1
    try pic.execInstruction(); // RRNCF 0x20, 1, 1
    try std.testing.expectEqual(0x55, pic.MEM[0x120]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);

    // Status Affected: N, Z
}

test "SUBFWB instruction" {
    // SUBFWB: (W) - (f) - (~C) -> dest. Status Affected: N, OV, C, DC, Z
    // borrow = NOT Carry; C=1 means no borrow.
    var pic = try asm2emu(
        \\      MOVLW 0x02
        \\      SUBFWB 0x10, 1, 0  ; doc: W=0x02 - f=0x03 - 0 = 0xFF, C=0, Z=0, N=1
        \\      MOVLW 0x05
        \\      SUBFWB 0x11, 1, 0  ; W=0x05 - f=0x02 - borrow(1) = 0x02, C=1
        \\      MOVLW 0x80
        \\      SUBFWB 0x12, 1, 0  ; W=0x80 - f=0x01 - 0 = 0x7F, signed OV=1
        \\      MOVLW 0x05
        \\      SUBFWB 0x13, 0, 0  ; d=0: W=0x05 - f=0x05 - 0 = 0x00 -> W, Z=1, C=1
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x03;
    pic.MEM[0x11] = 0x02;
    pic.MEM[0x12] = 0x01;
    pic.MEM[0x13] = 0x05;

    // Case 1 (doc): C=0 -> borrow=1? No: with C undefined at reset it is 0 -> borrow=1.
    // Set C explicitly to match the documented example (C=1 -> borrow=0).
    pic.REGS.STATUS.*.C = 1;
    try pic.execInstruction(); // MOVLW 0x02
    try pic.execInstruction(); // SUBFWB 0x10, 1, 0 : 0x02 - 0x03 - 0 = 0xFF
    try std.testing.expectEqual(0xFF, pic.MEM[0x10]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // (0x2&F) - (0x3&F) borrows
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV); // same sign, no overflow

    // Case 2: previous C=0 -> borrow=1: 0x05 - 0x02 - 1 = 0x02
    try pic.execInstruction(); // MOVLW 0x05
    try pic.execInstruction(); // SUBFWB 0x11, 1, 0
    try std.testing.expectEqual(0x02, pic.MEM[0x11]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // (5) - (2) - 1 = 2, no digit borrow

    // Case 3: previous C=1 -> borrow=0: 0x80 - 0x01 - 0 = 0x7F, signed overflow
    try pic.execInstruction(); // MOVLW 0x80
    try pic.execInstruction(); // SUBFWB 0x12, 1, 0
    try std.testing.expectEqual(0x7F, pic.MEM[0x12]);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow (0x80 >= 0x01)
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV); // -128 - 1 overflows
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // (0) - (1) digit borrow

    // Case 4: d=0, previous C=1 -> borrow=0: 0x05 - 0x05 - 0 = 0x00 -> W, f unchanged
    try pic.execInstruction(); // MOVLW 0x05
    try pic.execInstruction(); // SUBFWB 0x13, 0, 0
    try std.testing.expectEqual(0x00, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x05, pic.MEM[0x13]); // f unchanged
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC);

    // Status Affected: N, OV, C, DC, Z
}

test "TSTFSZ instruction" {
    // TSTFSZ: skip next instruction if (f) == 0; f is not modified. No status.
    var pic = try asm2emu(
        \\      TSTFSZ 0x10, 0     ; f=0x00 -> skip
        \\      MOVLW 0xFF         ; trap (skipped)
        \\      MOVLW 0x11         ; WREG = 0x11 (skip happened)
        \\      TSTFSZ 0x11, 0     ; f=0x42 -> no skip
        \\      MOVLW 0x22         ; WREG = 0x22 (no skip)
        \\      MOVLB 2
        \\      TSTFSZ 0x20, 1     ; BSR bank 2: f=0x00 -> skip
        \\      MOVLW 0xFF         ; trap (skipped)
        \\      MOVLW 0x44         ; WREG = 0x44 (skip happened)
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x00; // -> skip
    pic.MEM[0x11] = 0x42; // -> no skip
    pic.MEM[0x220] = 0x00; // -> skip
    pic.REGS.STATUS.*.Z = 0; // ensure status untouched by TSTFSZ

    // Case 1: f == 0 -> skip
    try pic.execInstruction(); // TSTFSZ 0x10 -> skip
    try pic.execInstruction(); // MOVLW 0x11 (trap skipped)
    try std.testing.expectEqual(0x11, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x00, pic.MEM[0x10]); // f unchanged
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z); // status not affected

    // Case 2: f != 0 -> no skip
    try pic.execInstruction(); // TSTFSZ 0x11 -> no skip
    try pic.execInstruction(); // MOVLW 0x22
    try std.testing.expectEqual(0x22, pic.REGS.WREG.*);
    try std.testing.expectEqual(0x42, pic.MEM[0x11]); // f unchanged

    // Case 3: BSR bank 2, f == 0 -> skip
    try pic.execInstruction(); // MOVLB 2
    try pic.execInstruction(); // TSTFSZ 0x20, 1 -> skip
    try pic.execInstruction(); // MOVLW 0x44 (trap skipped)
    try std.testing.expectEqual(0x44, pic.REGS.WREG.*);

    // Status Affected: None
}

test "NEGF instruction" {
    // NEGF: two's complement of (f) -> f. Status Affected: N, OV, C, DC, Z
    // NEGF is equivalent to 0 - f, so the subtraction flags follow accordingly.
    var pic = try asm2emu(
        \\      NEGF 0x10, 0       ; doc: 0x3A -> 0xC6, N=1
        \\      NEGF 0x11, 0       ; 0x00 -> 0x00, Z=1, C=1, DC=1
        \\      NEGF 0x12, 0       ; 0x80 -> 0x80, OV=1, N=1
        \\      NEGF 0x13, 0       ; 0x01 -> 0xFF, N=1, C=0
        \\  END
    );
    defer pic.deinit();
    pic.MEM[0x10] = 0x3A;
    pic.MEM[0x11] = 0x00;
    pic.MEM[0x12] = 0x80;
    pic.MEM[0x13] = 0x01;

    // Preset the flags that NEGF must overwrite to the opposite of the expected
    // result, so a NEGF that fails to update C/DC/OV is caught.
    pic.REGS.STATUS.*.C = 1;
    pic.REGS.STATUS.*.DC = 1;
    pic.REGS.STATUS.*.OV = 1;

    // Case 1: 0x3A -> 0xC6 (two's complement)
    try pic.execInstruction();
    try std.testing.expectEqual(0xC6, pic.MEM[0x10]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // 0 - 0x3A borrows
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // 0 - 0xA borrows
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV); // not 0x80, no overflow

    // Case 2: 0x00 -> 0x00, Z=1, no borrow
    try pic.execInstruction();
    try std.testing.expectEqual(0x00, pic.MEM[0x11]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.C); // 0 - 0 no borrow
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // no digit borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // Case 3: 0x80 -> 0x80 (two's complement of -128 is -128), signed overflow
    try pic.execInstruction();
    try std.testing.expectEqual(0x80, pic.MEM[0x12]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.OV); // NEG of 0x80 overflows
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // 0 - 0x80 borrows
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.DC); // low nibble 0 - 0, no borrow

    // Case 4: 0x01 -> 0xFF
    try pic.execInstruction();
    try std.testing.expectEqual(0xFF, pic.MEM[0x13]);
    try std.testing.expectEqual(1, pic.REGS.STATUS.*.N);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.Z);
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.C); // 0 - 1 borrows
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.DC); // 0 - 1 digit borrow
    try std.testing.expectEqual(0, pic.REGS.STATUS.*.OV);

    // Status Affected: N, OV, C, DC, Z
}
