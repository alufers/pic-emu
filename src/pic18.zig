const std = @import("std");
const ihex = @import("ihex.zig");
const gpio = @import("gpio.zig");
const PICGPIOPort = @import("pic_gpio_port.zig").PICGPIOPort;
const PICMSSP = @import("pic_mssp.zig").PICMSSP;
const PICTimer0 = @import("pic_timer0.zig").PICTimer0;

const readInt = std.mem.readInt;

pub const PeripheralError = error{
    ReadProhibited,
    WriteProhibited,
};

// Interface to a register belonging to some peripheral
pub const SpecialFunctionRegisterHandler = struct {
    const VTable = struct {
        reset: ?*const fn (self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) void = null,
        read: *const fn (self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8,
        write: *const fn (self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void,
    };
    vtable: *const VTable,

    pub fn reset(self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) void {
        if (self.vtable.reset) |reset_fn| {
            reset_fn(self, pic, addr);
        }
    }
    pub fn read(self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        return self.vtable.read(self, pic, addr);
    }
    pub fn write(self: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        return self.vtable.write(self, pic, addr, value);
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

    const RconReg = packed struct {
        /// Brown-out Reset Status bit (negated)
        BOR: u1,

        /// Power-on Reset Status bit (negated)
        POR: u1,

        /// Power-Down Detection Flag bit (negated)
        PD: u1,

        /// Watchdog Time-out Flag bit (negated)
        TO: u1,

        /// Reset Instruction flag bit (negated)
        RI: u1,

        /// Configuration Mismatch flag bit (negated)
        CM: u1,

        /// BOR Software Enable bit
        SBOREN: u1,

        /// Interrupt Priority Enable bit
        IPEN: u1,
    };

    const IntconReg = packed struct {
        RBIF: u1,
        INT0IF: u1,
        TMR0IF: u1,
        RBIE: u1,
        INT0IE: u1,
        TMR0IE: u1,

        /// Peripheral Interrupt Enable bit
        PEIE: u1,

        /// Global Interrupt Enable bit
        GIE: u1,
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

        PRODL: *u8,
        PRODH: *u8,

        RCON: *RconReg,
        INTCON: *IntconReg,
    };

    allocator: std.mem.Allocator,

    enableTrace: bool,

    PROG: []u8,
    configuration_bytes: []u8,

    MEM: []u8,

    // Registers
    PC: u21,
    REGS: RegAddrs,
    STACK: [31]u21, // 31 levels of hardware stack

    WREG_SHADOW: u8,
    STATUS_SHADOW: StatusReg,
    BSR_SHADOW: u8,

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
    MSSP1: PICMSSP,
    MSSP2: PICMSSP,
    Timer0: PICTimer0,

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

            .PRODL = &mem[0xFF3],
            .PRODH = &mem[0xFF4],

            .RCON = @ptrCast(&mem[0x0FD0]),
            .INTCON = @ptrCast(&mem[0x0FF2]),
        };
        pic.MSSP1 = PICMSSP.init();
        pic.MSSP2 = PICMSSP.init();
        pic.Timer0 = PICTimer0.init();
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

        pic.SFRHandlers[0xFD5 - 0xF00] = &pic.Timer0.T0CON_REG_HANDLER;
        pic.SFRHandlers[0xFD7 - 0xF00] = &pic.Timer0.TMR0H_REG_HANDLER;
        pic.SFRHandlers[0xFD6 - 0xF00] = &pic.Timer0.TMR0L_REG_HANDLER;

        pic.SFRHandlers[0xFC9 - 0xF00] = &pic.MSSP1.BUF_REG_HANDLER;
        pic.SFRHandlers[0xFC8 - 0xF00] = &pic.MSSP1.ADD_REG_HANDLER;
        pic.SFRHandlers[0xFC7 - 0xF00] = &pic.MSSP1.STAT_REG_HANDLER;
        pic.SFRHandlers[0xFC6 - 0xF00] = &pic.MSSP1.CON1_REG_HANDLER;
        pic.SFRHandlers[0xFC5 - 0xF00] = &pic.MSSP1.CON2_REG_HANDLER;

        pic.SFRHandlers[0xF6A - 0xF00] = &pic.MSSP2.BUF_REG_HANDLER;
        pic.SFRHandlers[0xF69 - 0xF00] = &pic.MSSP2.ADD_REG_HANDLER;
        pic.SFRHandlers[0xF68 - 0xF00] = &pic.MSSP2.STAT_REG_HANDLER;
        pic.SFRHandlers[0xF67 - 0xF00] = &pic.MSSP2.CON1_REG_HANDLER;
        pic.SFRHandlers[0xF66 - 0xF00] = &pic.MSSP2.CON2_REG_HANDLER;

        // Reset SFR handlers
        for (pic.SFRHandlers, 0..) |handler, offset| {
            if (handler) |h| {
                h.reset(pic, 0xF00 + @as(u16, @intCast(offset)));
            }
        }

        pic.enableTrace = false;

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

    pub fn loadRom(self: *PIC18, reader: *std.Io.Reader) !void {
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

    fn printInstruction(self: *PIC18, instr: u16, comptime fmt: []const u8, args: anytype) void {
        if (self.enableTrace) {
            std.debug.print("0x{x:0>4} INST: {b:0>16} (0x{x:0>4}) " ++ fmt, .{ self.PC - 2, instr, instr } ++ args);
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
        // as the "Access RAM" and is composed of GPRs. The
        // upper half is where the device's SFRs are mapped.
        // These two areas are mapped contiguously in the
        // Access Bank and can be addressed in a linear fashion
        // by an eight-bit address
        const bank: u16 = if (addr < 96) 0 else 15;
        return bank * 256 + addr;
    }

    // Checks whether the access is done via indirect addressing (using the FSR registers),
    // and acts accordingly
    // Otheriwse returns the address as-is
    fn resolveIndirect(self: *PIC18, full_addr: u16) !u16 {
        if (full_addr >= self.MEM.len) {
            return error.OutOfBoundsMemoryAccess;
        }
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

    pub fn saveToShadow(self: *PIC18) void {
        self.WREG_SHADOW = self.REGS.WREG.*;
        self.STATUS_SHADOW = self.REGS.STATUS.*;
        self.BSR_SHADOW = self.REGS.BSR.*;
    }

    pub fn restoreFromShadow(self: *PIC18) void {
        self.REGS.WREG.* = self.WREG_SHADOW;
        self.REGS.STATUS.* = self.STATUS_SHADOW;
        self.REGS.BSR.* = self.BSR_SHADOW;
    }

    pub fn execInstruction(self: *PIC18) !void {
        self.Timer0.tick(self);
        const instruction = self.consumeProgWord();

        errdefer {
            self.enableTrace = true;
            self.printInstruction(instruction, "<----- ERROR\n", .{});
        }

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
                                    self.printInstruction(instruction, "NOP\n", .{});
                                } else if (nibble4 == 0b0100) {
                                    self.printInstruction(instruction, "CLRWDT\n", .{});
                                    @as(*u8, @ptrCast(&self.REGS.STATUS)).* = 0x00;
                                    self.REGS.STATUS.*.TO = 1;
                                    self.REGS.STATUS.*.PD = 1;
                                    // TODO: implement watchdog timer
                                } else if (nibble4 & 0b1100 != 0) { // TBLRD - Table read
                                    // supposedly the third nibble is 0000, but for some reason it is allowed to be non-zero
                                    const mm = instruction & 0x0003;

                                    // todo implement pre-increment, post incrmement based on tbptr
                                    try self.check(self.REGS.TBLPTRU.* & 0xF0 == 0, "device config acces via tblptr not implemented", .{});
                                    var tblptr: u21 = (@as(u21, self.REGS.TBLPTRU.* & 0x0F) << 16) | (@as(u21, self.REGS.TBLPTRH.*) << 8) | @as(u21, self.REGS.TBLPTRL.*);
                                    if (mm == 3) {
                                        tblptr += 1;
                                    }
                                    self.printInstruction(instruction, "TBLRD mm={}, tblptr=0x{x}\n", .{ mm, tblptr });
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
                            0b0001 => {
                                switch (nibble4 & 0b1110) {
                                    0b0000 => { // RETFIE - Return from interrupt
                                        const use_shadow = instruction & 0x0001 == 1;
                                        if (use_shadow) {
                                            self.restoreFromShadow();
                                        }

                                        try self.check(self.REGS.STKPTR.* > 0, "stack underflow on RETFIE", .{}); // TODO: implement stack underflow handling
                                        self.REGS.STKPTR.* -= 1;
                                        self.PC = self.STACK[self.REGS.STKPTR.*];
                                        self.REGS.INTCON.GIE = 1;
                                    },
                                    0b0010 => { // RETURN
                                        const use_shadow = instruction & 0x0001 == 1;
                                        if (use_shadow) {
                                            self.restoreFromShadow();
                                        }

                                        try self.check(self.REGS.STKPTR.* > 0, "stack underflow on RETURN", .{}); // TODO: implement stack underflow handling
                                        self.REGS.STKPTR.* -= 1;
                                        self.PC = self.STACK[self.REGS.STKPTR.*];

                                        self.printInstruction(instruction, "RETURN to 0x{x} (SP={})\n", .{ self.PC, self.REGS.STKPTR.* });
                                    },
                                    else => return error.InvalidInstruction,
                                }
                            },
                            else => return error.InvalidInstruction,
                        }
                    },
                    0b0001 => { // MOVLB Move literal to BSR
                        self.REGS.BSR.* = @intCast(instruction & 0x003F); // Load 6 bits only
                    },
                    0b1010 => { // XORLW - Exlusive OR Literal with W
                        self.REGS.WREG.* = self.REGS.WREG.* ^ @as(u8, @intCast(instruction & 0x00FF));
                        self.printInstruction(instruction, "XORLW 0x{x}\n", .{self.REGS.WREG.*});
                        self.REGS.STATUS.*.Z = if (self.REGS.WREG.* == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (self.REGS.WREG.* & 0x80 != 0) 1 else 0;
                    },
                    0b1101 => { // MULLW - Multiply Literal with W
                        const k: u16 = instruction & 0x00FF;
                        const result: u16 = @as(u16, self.REGS.WREG.*) * k;
                        self.REGS.PRODH.* = @intCast(result >> 8);
                        self.REGS.PRODL.* = @intCast(result & 0xFF);
                        self.printInstruction(instruction, "MULLW 0x{x} -> PRODH=0x{x} PRODL=0x{x}\n", .{ k, self.REGS.PRODH.*, self.REGS.PRODL.* });
                    },
                    0b0100, 0b0101, 0b0110, 0b0111 => { // DECF Decrement f

                        // Status Affected C, DC, N, OV, Z

                        const dest_in_ram = (nibble2 & 0b0010) == 0b10; // If 'd' is '0', the result is stored in W. If 'd' is '1', the result is stored back in the register 'f' (default).
                        const use_bsr = (nibble2 & 0b0001) == 1; // If 'a' is '0', the Access Bank is selected. If 'a' is '1', the BSR is used to select the GPR bank.

                        self.printInstruction(instruction, "DECF use_bsr={} dest_in_ram={}  0x{x}\n", .{
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
                        self.printInstruction(instruction, "IORLW 0x{x}\n", .{self.REGS.WREG.*});
                        self.REGS.STATUS.*.Z = if (self.REGS.WREG.* == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (self.REGS.WREG.* & 0x80 != 0) 1 else 0;
                    },
                    0b1011 => { // ANDLW - AND Literal with W
                        self.REGS.WREG.* = self.REGS.WREG.* & @as(u8, @intCast(instruction & 0x00FF));
                        self.printInstruction(instruction, "ANDLW 0x{x}\n", .{self.REGS.WREG.*});
                        self.REGS.STATUS.*.Z = if (self.REGS.WREG.* == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (self.REGS.WREG.* & 0x80 != 0) 1 else 0;
                    },
                    0b1100 => { // RETLW- Return Literal to W
                        try self.check(self.REGS.STKPTR.* > 0, "stack underflow on RETURN", .{}); // TODO: implement stack underflow handling
                        self.REGS.STKPTR.* -= 1;
                        self.PC = self.STACK[self.REGS.STKPTR.*];
                        self.REGS.WREG.* = @intCast(instruction & 0x00FF);
                        self.printInstruction(instruction, "RETLW 0x{x}, return to 0x{x}\n", .{ self.REGS.WREG.*, self.PC });
                    },
                    0b1110 => { // MOVLW - Move Literal to W
                        self.REGS.WREG.* = @intCast(instruction & 0x00FF);
                        self.printInstruction(instruction, "MOVLW 0x{x}\n", .{self.REGS.WREG.*});
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0001 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10; // If 'd' is '0', the result is stored in W. If 'd' is '1', the result is stored back in the register 'f' (default).
                const use_bsr = (nibble2 & 0b0001) == 1; // if 0 the result is saved to WREG, otherwise it is saved back in the same register (the purpose is to set the Zero status)
                switch (nibble2 & 0b1100) {
                    0b0000 => { // IORWF - Inclusive OR W with f
                        self.printInstruction(instruction, "IORWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
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
                        self.printInstruction(instruction, "ANDWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
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
                    0b1000 => { // XORWF - Exclusive OR W with f
                        self.printInstruction(instruction, "XORWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) ^ self.REGS.WREG.*;
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
            0b0010 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10;
                const use_bsr = (nibble2 & 0b0001) == 1;
                switch (nibble2 & 0b1100) {
                    0b0000 => { // ADDWFC - Add W and Carry to f
                        self.printInstruction(instruction, "ADDWFC use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const w = self.REGS.WREG.*;
                        const c: u8 = self.REGS.STATUS.*.C;
                        const val = f +% w +% c;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.C = if (@as(u16, f) + @as(u16, w) + @as(u16, c) > 0xFF) 1 else 0;
                        self.REGS.STATUS.*.DC = if ((@as(u16, f & 0x0F) + @as(u16, w & 0x0F) + @as(u16, c)) > 0x0F) 1 else 0;
                        self.REGS.STATUS.*.OV = if (((~(f ^ w)) & (f ^ val) & 0x80) != 0) 1 else 0;
                    },
                    0b0100 => { // ADDWF - Add W to f
                        self.printInstruction(instruction, "ADDWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const w = self.REGS.WREG.*;
                        const val = f +% w;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.C = if (@as(u16, f) + @as(u16, w) > 0xFF) 1 else 0;
                        self.REGS.STATUS.*.DC = if ((@as(u16, f & 0x0F) + @as(u16, w & 0x0F)) > 0x0F) 1 else 0;
                        self.REGS.STATUS.*.OV = if (((~(f ^ w)) & (f ^ val) & 0x80) != 0) 1 else 0;
                    },
                    0b1000 => { // INCF - Increment f
                        self.printInstruction(instruction, "INCF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const val = f +% 1;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.C = if (f == 0xFF) 1 else 0;
                        self.REGS.STATUS.*.DC = if ((f & 0x0F) == 0x0F) 1 else 0;
                        self.REGS.STATUS.*.OV = if (f == 0x7F) 1 else 0;
                    },
                    0b1100 => { // DECFSZ - Decrement f, Skip if 0
                        self.printInstruction(instruction, "DECFSZ use_bsr={} dest_in_ram={}  0x{x}\n", .{
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
                        if (val == 0) self.PC += 2; // skip next instruction
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0011 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10;
                const use_bsr = (nibble2 & 0b0001) == 1;
                switch (nibble2 & 0b1100) {
                    0b0000 => { // RRCF - Rotate Right f through Carry
                        self.printInstruction(instruction, "RRCF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const old_carry: u8 = self.REGS.STATUS.*.C;
                        const val: u8 = (f >> 1) | (old_carry << 7);
                        self.REGS.STATUS.*.C = @intCast(f & 1);
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                    },
                    0b0100 => { // RLCF - Rotate Left f through Carry
                        self.printInstruction(instruction, "RLCF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const old_carry: u8 = self.REGS.STATUS.*.C;
                        const val: u8 = (f << 1) | old_carry;
                        self.REGS.STATUS.*.C = @intCast((f >> 7) & 1);
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                    },
                    0b1000 => { // SWAPF - Swap nibbles of f
                        self.printInstruction(instruction, "SWAPF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const val: u8 = (f << 4) | (f >> 4);
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0100 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10;
                const use_bsr = (nibble2 & 0b0001) == 1;
                switch (nibble2 & 0b1100) {
                    0b0100 => { // RLNCF - Rotate Left f (No Carry)
                        self.printInstruction(instruction, "RLNCF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const val: u8 = (f << 1) | (f >> 7);
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                    },
                    0b1000 => { // INFSNZ - Increment f, Skip if not 0
                        self.printInstruction(instruction, "INFSNZ use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });

                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const val, _ = @addWithOverflow(f, 1);
                        if (val != 0) {
                            self.PC += 2; // skip next instruction
                            self.printInstruction(instruction, "INFSNZ skipping next instruction because result is nonzero\n", .{});
                        }
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0101 => {
                const dest_in_ram = (nibble2 & 0b0010) == 0b10; // If 'd' is '0', the result is stored in W. If 'd' is '1', the result is stored back in the register 'f' (default).
                const use_bsr = (nibble2 & 0b0001) == 1; // if 0 the result is saved to WREG, otherwise it is saved back in the same register (the purpose is to set the Zero status)
                switch (nibble2 & 0b1100) {
                    0b0000 => { // MOVF
                        self.printInstruction(instruction, "MOVF use_bsr={} dest_in_ram={}  0x{x}\n", .{
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
                    0b1000 => { // SUBWFB - Subtract W from f with Borrow
                        self.printInstruction(instruction, "SUBWFB use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const w = self.REGS.WREG.*;
                        const borrow: u8 = 1 - self.REGS.STATUS.*.C; // C=1 means no borrow
                        const full: i16 = @as(i16, f) - @as(i16, w) - @as(i16, borrow);
                        const val: u8 = @truncate(@as(u16, @bitCast(full)));
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.C = if (full >= 0) 1 else 0;
                        self.REGS.STATUS.*.DC = if ((@as(i16, f & 0x0F) - @as(i16, w & 0x0F) - @as(i16, borrow)) >= 0) 1 else 0;
                        self.REGS.STATUS.*.OV = if (((f ^ w) & (f ^ val) & 0x80) != 0) 1 else 0;
                    },
                    0b1100 => { // SUBWF - Subtract W from f
                        self.printInstruction(instruction, "SUBWF use_bsr={} dest_in_ram={}  0x{x}\n", .{
                            use_bsr,
                            dest_in_ram,
                            instruction & 0x00FF,
                        });
                        const f = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        const w = self.REGS.WREG.*;
                        const val = f -% w;
                        if (dest_in_ram) {
                            try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
                        } else {
                            self.REGS.WREG.* = val;
                        }
                        self.REGS.STATUS.*.Z = if (val == 0) 1 else 0;
                        self.REGS.STATUS.*.N = if (val & 0x80 != 0) 1 else 0;
                        self.REGS.STATUS.*.C = if (f >= w) 1 else 0;
                        self.REGS.STATUS.*.DC = if ((f & 0x0F) >= (w & 0x0F)) 1 else 0;
                        self.REGS.STATUS.*.OV = if (((f ^ w) & (f ^ val) & 0x80) != 0) 1 else 0;
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b0110 => {
                const use_bsr = (nibble2 & 0b0001) == 1;
                switch (nibble2 & 0b1110) {
                    0b0100 => { // CPFSGT - Compare f with W, Skip if f > W
                        const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                        self.printInstruction(instruction, "CPFSGT 0x{x}\n", .{instruction & 0x00FF});
                        if (val > self.REGS.WREG.*) {
                            self.PC += 2; // skip next instruction
                            self.printInstruction(instruction, "CPFSGT skipping next instruction because f>W\n", .{});
                        }
                    },
                    0b1000 => { // SETF - Set f (to all ones)
                        self.printInstruction(instruction, "SETF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), 0xFF);
                    },
                    0b1010 => { // CLRF Clear register f
                        self.printInstruction(instruction, "CLRF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), 0);
                        self.REGS.STATUS.*.Z = 1;
                    },
                    0b1110 => { // MOVWF Move W to f
                        self.printInstruction(instruction, "MOVWF 0x{x}\n", .{instruction & 0x00FF});
                        try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), self.REGS.WREG.*);
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b1000 => { // BSF bit set f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                self.printInstruction(instruction, "BSF bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) | (@as(u8, 1) << bit_num);
                try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b1010 => { // BTFSS - Bit Test File, Skip if Set
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                self.printInstruction(instruction, "BTFSS bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                if ((val & (@as(u8, 1) << bit_num)) != 0) {
                    self.PC += 2; // skip next instruction
                    self.printInstruction(instruction, "BTFSS skipping next instruction because bit is set\n", .{});
                }
            },
            0b1011 => { // BTFSC - Bit Test File, Skip if Clear
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                self.printInstruction(instruction, "BTFSC bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF));
                if ((val & (@as(u8, 1) << bit_num)) == 0) {
                    self.PC += 2; // skip next instruction
                    self.printInstruction(instruction, "BTFSC skipping next instruction because bit is clear\n", .{});
                }
            },

            0b1001 => { // BCF Bit Clear f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                self.printInstruction(instruction, "BCF bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) & ~(@as(u8, 1) << bit_num);
                try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b0111 => { // BTG Bit Toggle f
                const bit_num: u3 = @intCast((nibble2 & 0b1110) >> 1);
                const use_bsr = (nibble2 & 0b0001) == 1;
                self.printInstruction(instruction, "BTG bit_num={} use_bsr={} 0x{x}\n", .{ bit_num, use_bsr, instruction & 0x00FF });
                const val = try self.memReadBanked(use_bsr, @intCast(instruction & 0x00FF)) ^ (@as(u8, 1) << bit_num);
                try self.memWriteBanked(use_bsr, @intCast(instruction & 0x00FF), val);
            },
            0b1100 => { // MOVFF Move fs to fd
                const second_word = self.consumeProgWord();
                try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid MOVFF", .{});
                const fs = instruction & 0x0FFF;
                const fd = second_word & 0x0FFF;

                self.printInstruction(instruction, "MOVFF src=0x{x} dst=0x{x}\n", .{ fs, fd });

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
                        self.printInstruction(instruction, "BRA n={} -> PC=0x{x}\n", .{ n, self.PC });
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b1110 => {
                switch (nibble2) {
                    0b0000 => { // BZ - Branch if Zero
                        const n: i8 = @bitCast(@as(u8, @intCast(instruction & 0x00FF)));
                        if (self.REGS.STATUS.*.Z == 1) {
                            self.PC = @intCast(@as(i32, @intCast(self.PC)) + 2 * @as(i32, n));
                        }
                        self.printInstruction(instruction, "BZ n={} Z={} -> PC=0x{x}\n", .{ n, self.REGS.STATUS.*.Z, self.PC });
                    },
                    0b0001 => { // BNZ - Branch if Not Zero
                        const n: i8 = @bitCast(@as(u8, @intCast(instruction & 0x00FF)));
                        if (self.REGS.STATUS.*.Z == 0) {
                            self.PC = @intCast(@as(i32, @intCast(self.PC)) + 2 * @as(i32, n));
                        }
                        self.printInstruction(instruction, "BNZ n={} Z={} -> PC=0x{x}\n", .{ n, self.REGS.STATUS.*.Z, self.PC });
                    },
                    0b0010 => { // BC - Branch if Carry
                        const n: i8 = @bitCast(@as(u8, @intCast(instruction & 0x00FF)));
                        if (self.REGS.STATUS.*.C == 1) {
                            self.PC = @intCast(@as(i32, @intCast(self.PC)) + 2 * @as(i32, n));
                        }
                        self.printInstruction(instruction, "BC n={} C={} -> PC=0x{x}\n", .{ n, self.REGS.STATUS.*.C, self.PC });
                    },
                    0b0011 => { // BNC - Branch if Not Carry
                        const n: i8 = @bitCast(@as(u8, @intCast(instruction & 0x00FF)));
                        if (self.REGS.STATUS.*.C == 0) {
                            self.PC = @intCast(@as(i32, @intCast(self.PC)) + 2 * @as(i32, n));
                        }
                        self.printInstruction(instruction, "BNC n={} C={} -> PC=0x{x}\n", .{ n, self.REGS.STATUS.*.C, self.PC });
                    },
                    0b1100, 0b1101 => { // CALL - Call subroutine
                        const use_shadow = (nibble2 & 0b0001) == 1;

                        if (use_shadow) {
                            self.saveToShadow();
                        }

                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid CALL", .{});
                        try self.check(self.REGS.STKPTR.* < self.STACK.len, "stack overflow not implemented", .{}); // TODO: implement stack overflow handling
                        self.STACK[self.REGS.STKPTR.*] = self.PC;
                        self.REGS.STKPTR.* += 1;
                        self.printInstruction(instruction, "CALL to 0x{x} (PC=0x{x})\n", .{ self.PC, (@as(u21, second_word & 0x0FFF) << 9) | (@as(u21, instruction & 0x00FF) << 1) });
                        self.PC = (@as(u21, second_word & 0x0FFF) << 9) | (@as(u21, instruction & 0x00FF) << 1);
                    },
                    0b1110 => { // LFSR - Load FSR (File select register)
                        const FSR_num: u8 = @intCast((instruction & 0x00F0) >> 4);
                        try self.check(FSR_num <= 2, "FSR_num too big", .{});
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid LFSR", .{});
                        const val = (instruction & 0x000F) << 8 | (second_word & 0x0FFF);
                        self.printInstruction(instruction, "LFSR: num={} 0x{x}\n", .{ FSR_num, val });
                        try self.setFSR(FSR_num, val);
                    },
                    0b1111 => { // GOTO
                        const second_word = self.consumeProgWord();
                        try self.check((second_word & 0xF000) >> 12 == 0b1111, "invalid GOTO", .{});

                        self.PC = (@as(u21, second_word & 0x0FFF) << 9) | (@as(u21, instruction & 0x00FF) << 1);
                        self.printInstruction(instruction, "GOTO ({b} {b}): 0x{x}\n", .{ instruction, second_word, self.PC });
                    },
                    else => return error.InvalidInstruction,
                }
            },
            0b1111 => { // Indicates second word of a two-word instruction
                // The only way to end up here is trying to skip over a two-word instruction by a branch instruction
                // Do nothing, it is a NOP.
                self.printInstruction(instruction, "DUMMY - skipped over two word instrctions", .{});
            },
        }
    }

    pub fn deinit(self: *PIC18) void {
        self.allocator.free(self.MEM);
        self.allocator.free(self.PROG);
        self.allocator.free(self.configuration_bytes);
        self.allocator.destroy(self); // Does this make sense?
    }
};
