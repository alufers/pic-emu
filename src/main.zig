const std = @import("std");
const ihex = @import("ihex.zig");
const gpio = @import("gpio.zig");

test {
    _ = @import("instr_test.zig");
    _ = @import("e2e_test.zig");
}

const readInt = std.mem.readInt;

pub const PeripheralError = error{
    ReadProhibited,
    WriteProhibited,
};

pub const SpecialFunctionRegisterVTable = struct {
    reset: ?*const fn (self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) void = null,
    read: *const fn (self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8,
    write: *const fn (self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void,
};

pub const SpecialFunctionRegisterHandler = struct {
    vtable: *const SpecialFunctionRegisterVTable,

    fn reset(self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) void {
        if (self.vtable.reset) |reset_fn| {
            reset_fn(self, pic, addr);
        }
    }
    fn read(self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        return self.vtable.read(self, pic, addr);
    }
    fn write(self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        return self.vtable.write(self, pic, addr, value);
    }
};

pub const PICGPIOPort = struct {
    PORT_REG_HANDLER: SpecialFunctionRegisterHandler,
    TRIS_REG_HANDLER: SpecialFunctionRegisterHandler,
    LAT_REG_HANDLER: SpecialFunctionRegisterHandler,

    pins: [8]?*gpio.GPIOPin,

    fn init() PICGPIOPort {
        return PICGPIOPort{
            .PORT_REG_HANDLER = .{
                .vtable = &.{
                    .read = portRead,
                    .write = portWrite,
                },
            },
            .TRIS_REG_HANDLER = .{
                .vtable = &.{
                    .reset = trisReset,
                    .read = trisRead,
                    .write = trisWrite,
                },
            },
            .LAT_REG_HANDLER = .{
                .vtable = &.{
                    .read = latRead,
                    .write = latWrite,
                },
            },

            .pins = .{ null, null, null, null, null, null, null, null },
        };
    }

    fn portWrite(sfrReg: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        const self: *PICGPIOPort = @alignCast(@fieldParentPtr("PORT_REG_HANDLER", sfrReg));
        for (self.pins, 0..) |pin, idx| {
            if (pin) |p| {
                p.write((value & (@as(u8, 1) << @intCast(idx))) != 0);
            }
        }

        // Write the value to memory anyway for readout of unconnected pins
        pic.MEM[addr] = value;
    }
    fn latWrite(sfrReg: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        const self: *PICGPIOPort = @alignCast(@fieldParentPtr("LAT_REG_HANDLER", sfrReg));
        return try self.PORT_REG_HANDLER.write(pic, addr, value);
    }
    fn portRead(sfrReg: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        const self: *PICGPIOPort = @alignCast(@fieldParentPtr("PORT_REG_HANDLER", sfrReg));
        const mem_val = pic.MEM[addr];
        var result: u8 = 0;
        for (self.pins, 0..) |pin, idx| {
            if (pin) |p| {
                if (p.read()) {
                    result |= @as(u8, 1) << @intCast(idx);
                }
            } else {
                // If pin not connected, read from memory
                if ((mem_val & (@as(u8, 1) << @intCast(idx))) != 0) {
                    result |= @as(u8, 1) << @intCast(idx);
                }
            }
        }
        return 0;
    }

    fn trisReset(_: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) void {
        pic.MEM[addr] = 0xFF; // default to all inputs
    }

    fn trisWrite(sfrReg: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        const self: *PICGPIOPort = @alignCast(@fieldParentPtr("TRIS_REG_HANDLER", sfrReg));
        for (0..8) |idx| {
            const direction = if ((value & (@as(u8, 1) << @intCast(idx))) != 0) gpio.GPIOMode.Input else gpio.GPIOMode.Output;
            if (self.pins[idx]) |p| {
                p.setMode(direction);
            }
        }
        pic.MEM[addr] = value;
    }
    fn trisRead(_: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        return pic.MEM[addr];
    }

    fn latRead(_: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        return pic.MEM[addr];
    }
};

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

        /// Bank select register
        BSR: *u8,

        /// Top of stack pointer
        STKPTR: *u8,
    };

    allocator: std.mem.Allocator,

    PROG: []u8,
    configuration_bytes: []u8,

    MEM: []u8,

    // Registers
    PC: u21,
    REGS: RegAddrs,
    STACK: [31]u21, // 31 levels of hardware stack

    /// Maps to memory addresses from 0xF00 to 0xFFF,
    /// If Some, read/write to this register is handled by the vtable, otherwise it is direct memory access
    SFRHandlers: [256]?*SpecialFunctionRegisterHandler,

    GPIOPortA: PICGPIOPort,
    GPIOPortB: PICGPIOPort,
    GPIOPortC: PICGPIOPort,
    GPIOPortD: PICGPIOPort,
    GPIOPortE: PICGPIOPort,
    GPIOPortF: PICGPIOPort,
    GPIOPortG: PICGPIOPort,

    pub fn init(allocator: std.mem.Allocator) *PIC18 {
        // Allocate full 2Mbyte program memory space
        const prog = allocator.alloc(u8, 2 * 1024 * 1024) catch unreachable;
        @memset(prog, 0);

        // 9 bytes of configuration bytes
        const dci = allocator.alloc(u8, 13) catch unreachable;
        @memset(dci, 0);

        const mem = allocator.alloc(u8, 256 * 16) catch unreachable; // PIC18F67K22 has 16 banks each,  256 bytes
        @memset(mem, 0);

        var pic = allocator.create(PIC18) catch unreachable;

        pic.allocator = allocator;
        pic.PROG = prog;
        pic.MEM = mem;
        pic.configuration_bytes = dci;
        pic.PC = 0;
        pic.STACK = [_]u21{0} ** 31;
        pic.SFRHandlers = [_]?*SpecialFunctionRegisterHandler{null} ** 256;
        pic.REGS = RegAddrs{
            .TBLPTRH = &mem[0xFF7],
            .TBLPTRL = &mem[0xFF6],
            .TBLPTRU = &mem[0xFF8],
            .TBLAT = &mem[0xFF5],
            .WREG = &mem[0xFE8],
            .FSR0L = &mem[0xFE9],
            .FSR0H = &mem[0xFEA],
            .FSR1L = &mem[0xFE1],
            .FSR1H = &mem[0xFE2],
            .FSR2L = &mem[0xFD9],
            .FSR2H = &mem[0xFDA],
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

            .BSR = &mem[0xFE0],
            .STKPTR = &mem[0xFFC],
        };
        pic.GPIOPortA = PICGPIOPort.init();
        pic.GPIOPortB = PICGPIOPort.init();
        pic.GPIOPortC = PICGPIOPort.init();
        pic.GPIOPortD = PICGPIOPort.init();
        pic.GPIOPortE = PICGPIOPort.init();
        pic.GPIOPortF = PICGPIOPort.init();
        pic.GPIOPortG = PICGPIOPort.init();

        pic.SFRHandlers[0xF80 - 0xF00] = &pic.GPIOPortA.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF92 - 0xF00] = &pic.GPIOPortA.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF89 - 0xF00] = &pic.GPIOPortA.LAT_REG_HANDLER;

        pic.SFRHandlers[0xF81 - 0xF00] = &pic.GPIOPortB.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF93 - 0xF00] = &pic.GPIOPortB.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF8A - 0xF00] = &pic.GPIOPortB.LAT_REG_HANDLER;

        pic.SFRHandlers[0xF82 - 0xF00] = &pic.GPIOPortC.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF94 - 0xF00] = &pic.GPIOPortC.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF8B - 0xF00] = &pic.GPIOPortC.LAT_REG_HANDLER;

        pic.SFRHandlers[0xF83 - 0xF00] = &pic.GPIOPortD.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF95 - 0xF00] = &pic.GPIOPortD.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF8C - 0xF00] = &pic.GPIOPortD.LAT_REG_HANDLER;

        pic.SFRHandlers[0xF84 - 0xF00] = &pic.GPIOPortE.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF96 - 0xF00] = &pic.GPIOPortE.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF8D - 0xF00] = &pic.GPIOPortE.LAT_REG_HANDLER;

        pic.SFRHandlers[0xF85 - 0xF00] = &pic.GPIOPortF.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF97 - 0xF00] = &pic.GPIOPortF.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF8E - 0xF00] = &pic.GPIOPortF.LAT_REG_HANDLER;

        pic.SFRHandlers[0xF86 - 0xF00] = &pic.GPIOPortG.PORT_REG_HANDLER;
        pic.SFRHandlers[0xF98 - 0xF00] = &pic.GPIOPortG.TRIS_REG_HANDLER;
        pic.SFRHandlers[0xF8F - 0xF00] = &pic.GPIOPortG.LAT_REG_HANDLER;

        // Reset SFR handlers
        for (pic.SFRHandlers, 0..) |handler, offset| {
            if (handler) |h| {
                h.reset(pic, 0xF00 + @as(u16, @intCast(offset)));
            }
        }
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
            const bank: u16 = self.REGS.BSR.*;
            return bank * 256 + addr;
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

    fn memWriteBanked(self: *PIC18, use_bsr: bool, addr: u8, val: u8) !void {
        const full_addr = try self.resolveIndirect(try self.accessBankFullAddr(use_bsr, addr));
        try self.memWrite(full_addr, val);
    }

    fn memReadBanked(self: *PIC18, use_bsr: bool, addr: u8) !u8 {
        const full_addr = try self.resolveIndirect(try self.accessBankFullAddr(use_bsr, addr));
        return self.memRead(full_addr);
    }

    fn memRead(self: *PIC18, full_addr: u16) !u8 {
        if (full_addr >= 0xF00) {
            if (self.SFRHandlers[full_addr - 0xF00]) |handler| {
                return try handler.read(self, full_addr);
            }
        }
        return self.MEM[full_addr];
    }

    fn memWrite(self: *PIC18, full_addr: u16, val: u8) !void {
        if (full_addr >= 0xF00) {
            if (self.SFRHandlers[full_addr - 0xF00]) |handler| {
                try handler.write(self, full_addr, val);
                return;
            }
        }

        self.MEM[full_addr] = val;
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

    pub fn getFSR(self: *PIC18, FSR_num: u8) !u16 {
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
        const nibble3 = @as(u4, @intCast((instruction & 0x00F0) >> 4));
        const nibble4 = @as(u4, @intCast(instruction & 0x000F));
        switch (nibble1) {
            0b0000 => {
                switch (nibble2) {
                    0b0000 => {
                        switch (nibble3) {
                            0b0000 => {
                                if (nibble4 == 0b000) {
                                    std.debug.print("NOP\n", .{});
                                } else if (nibble4 & 0b1100 != 0) { // TBLRD - Table read
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
                                } else {
                                    return error.InvalidInstruction;
                                }
                            },
                            0b0001 => { // RETURN
                                const use_shadow = instruction & 0x0001 == 1;
                                try self.check(!use_shadow, "shadow registers not implemented", .{}); // TODO: implement this

                                try self.check(self.REGS.STKPTR.* > 0, "stack underflow on RETURN", .{}); // TODO: implement stack underflow handling
                                self.REGS.STKPTR.* -= 1;
                                self.PC = self.STACK[self.REGS.STKPTR.*];

                                std.debug.print("RETURN to 0x{x} (SP={})\n", .{ self.PC, self.REGS.STKPTR.* });
                            },
                            else => return error.InvalidInstruction,
                        }
                    },
                    0b0001 => { // MOVLB Move literal to BSR
                        self.REGS.BSR.* = @intCast(instruction & 0x003F); // Load 6 bits only
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
                        const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) -% 1;

                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.OV = if (val == 0x7F) 1 else 0; // overflow if decrementing from 0x80 to 0x7F
                        self.REGS.STATUS.*.DC = if (val & 0x0F == 0x0F) 0 else 1; // digit carry is set if borrow from bit 4
                        self.REGS.STATUS.*.C = if (val == 0xFF) 0 else 1; // carry is set if borrow from bit 7
                    },
                    0b1001 => { // IORLW - Inclusive OR Literal with W
                        self.REGS.WREG.* = self.REGS.WREG.* | @as(u8, @intCast(instruction & 0x00FF));
                        std.debug.print("IORLW 0x{x}\n", .{self.REGS.WREG.*});
                        self.REGS.STATUS.*.Z = if (self.REGS.WREG.* == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (self.REGS.WREG.* & 0x80 != 0) 1 else 0;
                    },
                    0b1011 => { // ANDLW - AND Literal with W
                        self.REGS.WREG.* = self.REGS.WREG.* & @as(u8, @intCast(instruction & 0x00FF));
                        std.debug.print("ANDLW 0x{x}\n", .{self.REGS.WREG.*});
                        self.REGS.STATUS.*.Z = if (self.REGS.WREG.* == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (self.REGS.WREG.* & 0x80 != 0) 1 else 0;
                    },
                    0b1100 => { // RETLW- Return Literal to W
                        try self.check(self.REGS.STKPTR.* > 0, "stack underflow on RETURN", .{}); // TODO: implement stack underflow handling
                        self.REGS.STKPTR.* -= 1;
                        self.PC = self.STACK[self.REGS.STKPTR.*];
                        self.REGS.WREG.* = @intCast(instruction & 0x00FF);
                        std.debug.print("RETLW 0x{x}, return to 0x{x}\n", .{ self.REGS.WREG.*, self.PC });
                    },
                    0b1110 => { // MOVLW - Move Literal to W
                        self.REGS.WREG.* = @intCast(instruction & 0x00FF);
                        std.debug.print("MOVLW 0x{x}\n", .{self.REGS.WREG.*});
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0001 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10; // If ‘d’ is ‘0’, the result is stored in W. If ‘d’ is ‘1’, the result is stored back in the register ‘f’ (default).
                const use_bsr = (nibble2 & 0b0001) == 1; // if 0 the result is saved to WREG, otherwise it is saved back in the same register (the purpose is to set the Zero status)
                switch (nibble2 & 0b1100) {
                    0b0000 => { // IORWF - Inclusive OR W with f
                        std.debug.print("IORWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) | self.REGS.WREG.*;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                    },
                    0b0100 => { // ANDWF - AND W with f
                        std.debug.print("ANDWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) & self.REGS.WREG.*;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0101 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10; // If ‘d’ is ‘0’, the result is stored in W. If ‘d’ is ‘1’, the result is stored back in the register ‘f’ (default).
                const use_bsr = (nibble2 & 0b0001) == 1; // if 0 the result is saved to WREG, otherwise it is saved back in the same register (the purpose is to set the Zero status)
                switch (nibble2 & 0b1100) {
                    0b0000 => { // MOVF
                        std.debug.print("MOVF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
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
                    0b1000 => { // SETF - Set f (to all ones)
                        std.debug.print("SETF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), 0xFF);
                    },
                    0b1010 => { // CLRF Clear register f
                        std.debug.print("CLRF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), 0);
                        self.REGS.STATUS.*.Z = 1;
                    },
                    0b1110 => { // MOVWF Move W to f
                        std.debug.print("MOVWF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), self.REGS.WREG.*);
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b1000 => { // BSF bit set f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                std.debug.print("BSF bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) | (@as(u8, 1) << bit_num);
                try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b1011 => { // BTFSC - Bit Test File, Skip if Clear
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                std.debug.print("BTFSC bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                if ((val & (@as(u8, 1) << bit_num)) == 0) {
                    self.PC += 2; // skip next instruction
                    std.debug.print("BTFSC skipping next instruction because bit is clear\n", .{});
                }
            },
            0b1001 => { // BCF Bit Clear f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                std.debug.print("BCF bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) & ~(@as(u8, 1) << bit_num);
                try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b0111 => { // BTG Bit Toggle f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                std.debug.print("BTG bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) ^ (@as(u8, 1) << bit_num);
                try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b1100 => { // MOVFF Move fs to fd
                const second_word = self.consumeProgWord();
                try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid MOVFF", .{});
                const fs = instruction & 0x0FFF;
                const fd = second_word & 0x0FFF;

                std.debug.print("MOVFF src=0x{x} dst=0x{x}\n", .{ fs, fd });

                // resolve indirect handles side effects on FSRs
                const indirect_fs = try self.resolveIndirect(fs);
                const indirect_fd = try self.resolveIndirect(fd);

                try self.memWrite(indirect_fd, try self.memRead(indirect_fs));
            },
            0b1101 => {
                switch (nibble2 & 0b1000) {
                    0b0000 => { // BRA - Unconditional branch
                        const n: i11 = @bitCast(@as(u11, @intCast(instruction & 0b0000_0111_1111_1111)));
                        self.PC = @intCast(@as(i32, self.PC) + 2 * @as(i32, n));
                        std.debug.print("BRA n={} -> PC=0x{x}\n", .{ n, self.PC });
                    },
                    else => return error.InvalidInstruction,
                }
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
                    0b1100, 0b1101 => { // CALL - Call subroutine
                        const use_shadow = (nibble2 & 0b0001) == 1;
                        try self.check(!use_shadow, "shadow registers not implemented", .{}); // TODO: implement this
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid CALL", .{});
                        try self.check(self.REGS.STKPTR.* < self.STACK.len, "stack overflow not implemented", .{}); // TODO: implement stack overflow handling
                        self.STACK[self.REGS.STKPTR.*] = self.PC;
                        self.REGS.STKPTR.* += 1;
                        std.debug.print("CALL to 0x{x} (PC=0x{x})\n", .{ self.PC, (@as(u21, second_word & 0x0FFF) << 9) | (@as(u21, instruction & 0x00FF) << 1) });
                        self.PC = (@as(u21, second_word & 0x0FFF) << 9) | (@as(u21, instruction & 0x00FF) << 1);
                    },
                    0b1110 => { // LFSR - Load FSR (File select register)
                        const FSR_num: u8 = @intCast((instruction & 0x00F0) >> 4);
                        try self.check(FSR_num <= 2, "FSR_num too big", .{});
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid LFSR", .{});
                        const val = (instruction & 0x000F) << 8 | (second_word & 0x0FFF);
                        std.debug.print("LFSR: num={} 0x{x}\n", .{ FSR_num, val });
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
        self.allocator.destroy(self); // Does this make sense?
    }
};

fn processData(_: void, offset: u32, data: []const u8) !void {
    std.debug.print("read slice @ 0x{x}: {x}\n", .{ offset, data });
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var file = try std.fs.cwd().openFile("./pilot.X.production.hex", .{ .mode = .read_only });
    defer file.close();

    var file_buffer: [1024]u8 = undefined;
    var rdr = file.reader(&file_buffer);

    var pic = PIC18.init(allocator);
    try pic.loadRom(&rdr.interface);

    var spi_cs_pin = gpio.LoggingGPIOPin.init("A.5 [FLASH_CS]");

    pic.GPIOPortA.pins[5] = &spi_cs_pin.interface;

    var cnt: u32 = 0;
    for (0..9999) |_| {
        if (pic.PC == 0x01b1ce) {
            cnt += 1;
            if (cnt == 1) {
                // Print
            }
            std.debug.print("======PC hit 0x01b1ce! count={}\n", .{cnt});
        }
        pic.execInstruction() catch |err| {
            // Dump memory to file
            var out_file = try std.fs.cwd().createFile("dump.bin", .{ .truncate = true });
            defer out_file.close();
            try out_file.writeAll(pic.MEM);
            return err;
        };
    }
}
