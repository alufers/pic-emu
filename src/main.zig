const std = @import("std");
const ihex = @import("ihex.zig");

test {
    _ = @import("emu_test.zig");
}

const readInt = std.mem.readInt;

// TODO: move regs into memory (WREG, FSR)

pub const PIC18 = struct {
    /// https://onlinedocs.microchip.com/oxy/GUID-0C48BD90-048C-4F4F-9800-5D5269497C89-en-US-3/GUID-06A816BE-05BC-452E-AE33-7D4FD59DE5FD.html#GUID-06A816BE-05BC-452E-AE33-7D4FD59DE5FD
    const StatusReg = packed struct {
        /// Carry
        C: u1,
        /// Digit carry
        DC: u1,
        /// Zero
        Z: u1,
        /// Overflow
        OV: u1,
        /// Negative
        N: u1,
        /// Power down
        PD: u1,
        /// Timeout
        TO: u1,
        unused: u1,
    };
    const RegAddrs = struct {
        TBLPTRH: *u8,
        TBLPTRL: *u8,
        TBLPTRU: *u8,
        TBLAT: *u8,
        WREG: *u8,
        FSR0L: *u8,
        FSR0H: *u8,
        FSR1L: *u8,
        FSR1H: *u8,
        FSR2L: *u8,
        FSR2H: *u8,
        STATUS: *StatusReg,
        INDF0: *u8,
        POSTINC0: *u8,
        POSTDEC0: *u8,
        PREINC0: *u8,
        PLUSW0: *u8,
        INDF1: *u8,
        POSTINC1: *u8,
        POSTDEC1: *u8,
        PREINC1: *u8,
        PLUSW1: *u8,
        INDF2: *u8,
        POSTINC2: *u8,
        POSTDEC2: *u8,
        PREINC2: *u8,
        PLUSW2: *u8,
    };

    allocator: std.mem.Allocator,

    PROG: []u8,
    configuration_bytes: []u8,

    MEM: []u8,

    // Registers
    PC: u21,

    REGS: RegAddrs,

    pub fn init(allocator: std.mem.Allocator) PIC18 {
        // Allocate full 2Mbyte program memory space
        const prog = allocator.alloc(u8, 2 * 1024 * 1024) catch unreachable;
        @memset(prog, 0);

        // 9 bytes of configuration bytes
        const dci = allocator.alloc(u8, 13) catch unreachable;
        @memset(dci, 0);

        const mem = allocator.alloc(u8, 256 * 16) catch unreachable; // PIC18F67K22 has 16 banks each,  256 bytes
        @memset(mem, 0);
        const pic = PIC18{
            .allocator = allocator,
            .PROG = prog,
            .MEM = mem,
            .configuration_bytes = dci,
            .PC = 0,
            .REGS = RegAddrs{
                .TBLPTRH = &mem[0xFF7],
                .TBLPTRL = &mem[0xFF6],
                .TBLPTRU = &mem[0xFF8],
                .TBLAT = &mem[0xFF5],
                .WREG = &mem[0xFE8],
                .FSR0L = &mem[0xFEA],
                .FSR0H = &mem[0xFEB],
                .FSR1L = &mem[0xFEC],
                .FSR1H = &mem[0xFED],
                .FSR2L = &mem[0xFEE],
                .FSR2H = &mem[0xFEF],
                .STATUS = @ptrCast(&mem[0xFD8]),

                .INDF0 = &mem[0xFEF],
                .POSTINC0 = &mem[0xFEE],
                .POSTDEC0 = &mem[0xFED],
                .PREINC0 = &mem[0xFEC],
                .PLUSW0 = &mem[0xFEB],

                .INDF1 = &mem[0xFE7],
                .POSTINC1 = &mem[0xFE6],
                .POSTDEC1 = &mem[0xFE5],
                .PREINC1 = &mem[0xFE4],
                .PLUSW1 = &mem[0xFE3],

                .INDF2 = &mem[0xFDF],
                .POSTINC2 = &mem[0xFDE],
                .POSTDEC2 = &mem[0xFDD],
                .PREINC2 = &mem[0xFDC],
                .PLUSW2 = &mem[0xFDB],
            },
        };
        return pic;
    }

    fn ihexCb(self: *PIC18, offset: u32, data: []const u8) !void {
        if (offset == 0x300000) {
            if (data.len == 13) {
                @memcpy(self.configuration_bytes, data);
            }
            return;
        }

        @memcpy(self.PROG[offset..][0..data.len], data);
    }

    pub fn loadRom(self: *PIC18, reader: *std.io.Reader) !void {
        // clear program memory
        @memset(self.PROG, 0);

        // parse hex file, ignore entry point
        _ = try ihex.parseData(reader, ihex.ParseMode{ .pedantic = true }, self, error{}, PIC18.ihexCb);
    }

    fn consumeProgWord(self: *PIC18) u16 {
        const w = readInt(u16, self.PROG[self.PC..][0..2], .little);
        self.PC += 2;
        return w;
    }

    fn check(self: *PIC18, cond: bool, comptime fmt: []const u8, args: anytype) !void {
        if (!cond) {
            std.debug.print("EMULATOR CHECK FAILED AT PC 0x{x}: " ++ fmt ++ "\n", .{self.PC} ++ args);
            return error.EmulatorError;
        }
    }

    fn accessBankFullAddr(self: *PIC18, use_bsr: bool, addr: u8) !u16 {
        if (use_bsr) {
            try self.check(false, "NON ACCESS BANK WRITE NOT IMPLEMENTED", .{});
        }
        // The Access Bank consists of the first 96 bytes of
        // memory (00h-5Fh) in Bank 0 and the last 160 bytes of
        // memory (60h-FFh) in Bank 15. The lower half is known
        // as the “Access RAM” and is composed of GPRs. The
        // upper half is where the device’s SFRs are mapped.
        // These two areas are mapped contiguously in the
        // Access Bank and can be addressed in a linear fashion
        // by an eight-bit address
        const bank: u16 = if (addr < 96) 0 else 15;
        return bank * 256 + addr;
    }

    fn resolveIndirect(self: *PIC18, full_addr: u16) !u16 {
        const ptr = &self.MEM[full_addr];
        // FSR0 indirect
        if (ptr == self.REGS.INDF0) {
            return try self.getFSR(0);
        } else if (ptr == self.REGS.POSTINC0) {
            const fsr = try self.getFSR(0);
            try self.setFSR(0, fsr +% 1);
            return fsr;
        } else if (ptr == self.REGS.POSTDEC0) {
            const fsr = try self.getFSR(0);
            try self.setFSR(0, fsr -% 1);
            return fsr;
        } else if (ptr == self.REGS.PREINC0) {
            const fsr = try self.getFSR(0) +% 1;
            try self.setFSR(0, fsr);
            return fsr;
        } else if (ptr == self.REGS.PLUSW0) {
            const fsr = try self.getFSR(0);
            const offset: i8 = @bitCast(self.REGS.WREG.*);
            return @intCast(@as(i32, fsr) + offset);
            // FSR1 indirect
        } else if (ptr == self.REGS.INDF1) {
            return try self.getFSR(1);
        } else if (ptr == self.REGS.POSTINC1) {
            const fsr = try self.getFSR(1);
            try self.setFSR(1, fsr +% 1);
            return fsr;
        } else if (ptr == self.REGS.POSTDEC1) {
            const fsr = try self.getFSR(1);
            try self.setFSR(1, fsr -% 1);
            return fsr;
        } else if (ptr == self.REGS.PREINC1) {
            const fsr = try self.getFSR(1) +% 1;
            try self.setFSR(1, fsr);
            return fsr;
        } else if (ptr == self.REGS.PLUSW1) {
            const fsr = try self.getFSR(1);
            const offset: i8 = @bitCast(self.REGS.WREG.*);
            return @intCast(@as(i32, fsr) + offset);
            // FSR2 indirect
        } else if (ptr == self.REGS.INDF2) {
            return try self.getFSR(2);
        } else if (ptr == self.REGS.POSTINC2) {
            const fsr = try self.getFSR(2);
            try self.setFSR(2, fsr +% 1);
            return fsr;
        } else if (ptr == self.REGS.POSTDEC2) {
            const fsr = try self.getFSR(2);
            try self.setFSR(2, fsr -% 1);
            return fsr;
        } else if (ptr == self.REGS.PREINC2) {
            const fsr = try self.getFSR(2) +% 1;
            try self.setFSR(2, fsr);
            return fsr;
        } else if (ptr == self.REGS.PLUSW2) {
            const fsr = try self.getFSR(2);
            const offset: i8 = @bitCast(self.REGS.WREG.*);
            return @intCast(@as(i32, fsr) + offset);
        }
        return full_addr;
    }

    fn memWrite(self: *PIC18, use_bsr: bool, addr: u8, val: u8) !void {
        const full_addr = try self.resolveIndirect(try self.accessBankFullAddr(use_bsr, addr));
        self.MEM[full_addr] = val;
    }

    fn memRead(self: *PIC18, use_bsr: bool, addr: u8) !u8 {
        const full_addr = try self.resolveIndirect(try self.accessBankFullAddr(use_bsr, addr));
        return self.MEM[full_addr];
    }

    fn setFSR(self: *PIC18, FSR_num: u8, val: u16) !void {
        const val_l: u8 = @intCast(val & 0xFF);
        const val_h: u8 = @intCast((val >> 8) & 0xFF);
        switch (FSR_num) {
            0 => {
                self.REGS.FSR0L.* = val_l;
                self.REGS.FSR0H.* = val_h;
            },
            1 => {
                self.REGS.FSR1L.* = val_l;
                self.REGS.FSR1H.* = val_h;
            },
            2 => {
                self.REGS.FSR2L.* = val_l;
                self.REGS.FSR2H.* = val_h;
            },
            else => return error.InvalidInstruction,
        }
    }

    fn getFSR(self: *PIC18, FSR_num: u8) !u16 {
        switch (FSR_num) {
            0 => {
                return @as(u16, self.REGS.FSR0H.*) << 8 | @as(u16, self.REGS.FSR0L.*);
            },
            1 => {
                return @as(u16, self.REGS.FSR1H.*) << 8 | @as(u16, self.REGS.FSR1L.*);
            },
            2 => {
                return @as(u16, self.REGS.FSR2H.*) << 8 | @as(u16, self.REGS.FSR2L.*);
            },
            else => return error.InvalidInstruction,
        }
    }

    pub fn execInstruction(self: *PIC18) !void {
        const instruction = self.consumeProgWord();
        std.debug.print("0x{x:0>4} INST: {b:0>16} (0x{x:0>4})\n", .{ self.PC - 2, instruction, instruction });
        const nibble1 = @as(u4, @intCast((instruction & 0xF000) >> 12));
        const nibble2 = @as(u4, @intCast((instruction & 0x0F00) >> 8));
        switch (nibble1) {
            0b0000 => {
                switch (nibble2) {
                    0b0000 => { // TBLRD
                        // supposedly the third nibble is 0000, but for some reason it is allowed to be non-zero
                        const mm = instruction & 0x0003;

                        // todo implement pre-increment, post incrmement based on tbptr
                        try self.check(self.REGS.TBLPTRU.* & 0xF0 == 0, "device config acces via tblptr not implemented", .{});
                        var tblptr: u21 = (@as(u21, self.REGS.TBLPTRU.* & 0x0F) << 16) | (@as(u21, self.REGS.TBLPTRH.*) << 8) | @as(u21, self.REGS.TBLPTRL.*);
                        if (mm == 3) {
                            tblptr += 1;
                        }
                        std.debug.print("TBLRD mm={}, tblptr=0x{x}\n", .{ mm, tblptr });
                        self.REGS.TBLAT.* = self.PROG[tblptr];
                        if (mm == 1) {
                            tblptr += 1;
                        } else if (mm == 2) {
                            tblptr -= 1;
                        }
                        // Write back TBLPTR
                        self.REGS.TBLPTRU.* = @intCast((tblptr >> 16) & 0x0F);
                        self.REGS.TBLPTRH.* = @intCast((tblptr >> 8) & 0xFF);
                        self.REGS.TBLPTRL.* = @intCast(tblptr & 0xFF);
                    },
                    0b0100, 0b0101, 0b0110, 0b0111 => { // DECF Decrement f

                        // Status Affected C, DC, N, OV, Z

                        const dest_in_ram = (nibble2 & 0b0010) == 0b10; // If ‘d’ is ‘0’, the result is stored in W. If ‘d’ is ‘1’, the result is stored back in the register ‘f’ (default).
                        const use_bsr = (nibble2 & 0b0001) == 1; // If ‘a’ is ‘0’, the Access Bank is selected. If ‘a’ is ‘1’, the BSR is used to select the GPR bank.

                        std.debug.print("DECF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const val = try self.memRead(use_bsr, @intCast(instruction & 0x00FF)) -% 1;

                        if (dest_in_ram) {
                            try self.memWrite(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.OV = if (val == 0x7F) 1 else 0; // overflow if decrementing from 0x80 to 0x7F
                        self.REGS.STATUS.*.DC = if (val & 0x0F == 0x0F) 0 else 1; // digit carry is set if borrow from bit 4
                        self.REGS.STATUS.*.C = if (val == 0xFF) 0 else 1; // carry is set if borrow from bit 7
                    },
                    0b1110 => { // MOVLW - Move Literal to W
                        self.REGS.WREG.* = @intCast(instruction & 0x00FF);
                        std.debug.print("MOVLW 0x{x}\n", .{self.REGS.WREG.*});
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0101 => {
                const use_bsr = (nibble2 & 0b0001) == 1;
                const dest_in_ram = (nibble2 & 0b0001) == 1; // if 0 the result is saved to WREG, otherwise it is saved back in the same register (the purpose is to set the Zero status)
                switch (nibble2 & 0b1100) {
                    0b0000 => { // MOVF
                        std.debug.print("MOVF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const val = try self.memRead(use_bsr, @intCast(instruction & 0x00FF));
                        if (dest_in_ram) {
                            try self.memWrite(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0110 => {
                const use_bsr = (nibble2 & 0b0001) == 1;
                switch (nibble2 & 0b1110) {
                    0b1010 => { // CLRF Clear register f
                        std.debug.print("CLRF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWrite(use_bsr, @intCast(instruction & 0x00FF), 0);
                        self.REGS.STATUS.*.Z = 1;
                    },
                    0b1110 => { // MOVWF Move W to f
                        std.debug.print("MOVWF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWrite(use_bsr, @intCast(instruction & 0x00FF), self.REGS.WREG.*);
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b1001 => { // BCF Bit Clear f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                std.debug.print("BCF bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memRead(use_bsr, @intCast(instruction & 0x00FF)) & ~(@as(u8, 1) << bit_num);
                try self.memWrite(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b1100 => { // MOVFF Move fs to fd
                const second_word = self.consumeProgWord();
                try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid MOVFF", .{});
                const fs = instruction & 0x0FFF;
                const fd = second_word & 0x0FFF;

                std.debug.print("MOVFF src=0x{x} dst=0x{x}\n", .{ fs, fd });

                self.MEM[fd] = self.MEM[fs]; // TODO: side effects?
            },
            0b1110 => {
                switch (nibble2) {
                    0b0001 => { // BNZ - Branch if Not Zero
                        const n: i8 = @bitCast(@as(u8, @intCast(instruction & 0x00FF)));
                        if (self.REGS.STATUS.*.Z == 0) {
                            self.PC = @intCast(@as(i32, @intCast(self.PC)) + 2 * @as(i32, n));
                        }
                        std.debug.print("BNZ n={} Z={} -> PC=0x{x}\n", .{ n, self.REGS.STATUS.*.Z, self.PC });
                    },
                    0b1110 => { // LFSR - Load FSR (File select register)
                        const FSR_num: u8 = @intCast((instruction & 0x00F0) >> 4);
                        try self.check(FSR_num <= 2, "FSR_num too big", .{});
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid LFSR", .{});
                        const val = (instruction & 0x000F) << 8 | (second_word & 0x0FFF);
                        std.debug.print("LFSR: 0x{x}\n", .{val});
                        try self.setFSR(FSR_num, val);
                    },
                    0b1111 => { // GOTO
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid GOTO", .{});

                        self.PC = (@as(u21, second_word & 0x0FFF) << 9) | (@as(u21, instruction & 0x00FF) << 1);
                        std.debug.print("GOTO ({b} {b}): 0x{x}\n", .{ instruction, second_word, self.PC });
                    },
                    else => return error.InvalidInstruction,
                }
            },
            else => return error.InvalidInstruction,
        }
    }

    pub fn deinit(self: *PIC18) void {
        self.allocator.free(self.MEM);
        self.allocator.free(self.PROG);
        self.allocator.free(self.configuration_bytes);
    }
};

fn processData(_: void, offset: u32, data: []const u8) !void {
    std.debug.print("read slice @ 0x{x}: {x}\n", .{ offset, data });
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var file = try std.fs.cwd().openFile("../pilot.X.production.hex", .{ .mode = .read_only });
    defer file.close();

    var file_buffer: [1024]u8 = undefined;
    var rdr = file.reader(&file_buffer);

    var pic = PIC18.init(allocator);
    try pic.loadRom(&rdr.interface);

    for (0..15) |_| {
        try pic.execInstruction();
    }
}
