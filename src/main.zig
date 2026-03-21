const std = @import("std");
const ihex = @import("ihex.zig");

test {
    _ = @import("emu_test.zig");
}

const readInt = std.mem.readInt;

// TODO: move regs into memory (WREG, FSR)

pub const PIC18 = struct {
    const StatusReg = packed struct {
        C: u1,
        DC: u1,
        Z: u1,
        OV: u1,
        N: u1,
        PD: u1,
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

    fn memWrite(self: *PIC18, use_bsr: bool, addr: u8, val: u8) !void {
        var bank: u16 = 0;
        if (use_bsr) {
            try self.check(false, "NON ACCESS BANK WRITE NOT IMPLEMENTED", .{});
        } else {
            // The Access Bank consists of the first 96 bytes of
            // memory (00h-5Fh) in Bank 0 and the last 160 bytes of
            // memory (60h-FFh) in Bank 15. The lower half is known
            // as the “Access RAM” and is composed of GPRs. The
            // upper half is where the device’s SFRs are mapped.
            // These two areas are mapped contiguously in the
            // Access Bank and can be addressed in a linear fashion
            // by an eight-bit address
            if (addr < 96) {
                // Access GPRs (bank 0)
                bank = 0;
            } else {
                // Access SFRs (bank 15)
                bank = 15;
            }
        }

        std.debug.print("MEM[0x{x}] = 0x{x} (bank: {})\n", .{ bank * 256 + addr, val, bank });

        self.MEM[bank * 256 + addr] = val;
    }

    fn memRead(self: *PIC18, use_bsr: bool, addr: u8) !u8 {
        var bank: u16 = 0;
        if (use_bsr) {
            try self.check(false, "NON ACCESS BANK WRITE NOT IMPLEMENTED", .{});
        } else {
            // The Access Bank consists of the first 96 bytes of
            // memory (00h-5Fh) in Bank 0 and the last 160 bytes of
            // memory (60h-FFh) in Bank 15. The lower half is known
            // as the “Access RAM” and is composed of GPRs. The
            // upper half is where the device’s SFRs are mapped.
            // These two areas are mapped contiguously in the
            // Access Bank and can be addressed in a linear fashion
            // by an eight-bit address
            if (addr < 96) {
                // Access GPRs (bank 0)
                bank = 0;
            } else {
                // Access SFRs (bank 15)
                bank = 15;
            }
        }

        return self.MEM[bank * 256 + addr];
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
                            try self.check(false, "Z status not implemented yet", .{});
                        } else {
                            self.REGS.WREG.* = val;
                        }
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0110 => {
                const use_bsr = (nibble2 & 0b0001) == 1;
                switch (nibble2 & 0b1110) {
                    0b1110 => { // MOVWF Move W to f
                        std.debug.print("MOVWF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWrite(use_bsr, @intCast(instruction & 0x00FF), self.REGS.WREG.*);
                    },
                    else => return error.InvalidInstruction,
                }
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

                    },
                    0b1110 => { // LFSR - Load FSR (File select register)
                        const FSR_num = (instruction & 0x00F0) >> 4;
                        try self.check(FSR_num <= 2, "FSR_num too big", .{});
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid LFSR", .{});
                        const val = (instruction & 0x000F) << 8 | (second_word & 0x0FFF);
                        std.debug.print("LFSR: 0x{x}\n", .{val});
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
