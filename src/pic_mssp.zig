const std = @import("std");
const pic18 = @import("pic18.zig");
const SpecialFunctionRegisterHandler = pic18.SpecialFunctionRegisterHandler;
const PIC18 = pic18.PIC18;
const PeripheralError = pic18.PeripheralError;

pub const SSPxSTAT = packed struct {
    /// BF: Buffer Full Status bit (Receive mode only).
    /// 1 = Receive is complete, SSPxBUF is full.
    /// 0 = Receive is not complete, SSPxBUF is empty.
    BF: u1,
    /// UA: Update Address bit. Used in I2C mode only.
    UA: u1,
    /// R/W: Read/Write Information bit. Used in I2C mode only.
    RW: u1,
    /// S: Start bit. Used in I2C mode only.
    S: u1,
    /// P: Stop bit. Used in I2C mode only.
    /// This bit is cleared when the MSSPx module is disabled; SSPEN is cleared.
    P: u1,
    /// D/A: Data/Address bit. Used in I2C mode only.
    DA: u1,
    /// CKE: SPI Clock Select bit.
    /// 1 = Transmit occurs on the transition from active to Idle clock state.
    /// 0 = Transmit occurs on the transition from Idle to active clock state.
    CKE: u1,
    /// SMP: Sample bit.
    /// SPI Master mode: 1 = Input data is sampled at the end of data output time.
    ///                  0 = Input data is sampled at the middle of data output time.
    /// SPI Slave mode: SMP must be cleared when SPI is used in Slave mode.
    SMP: u1,
};

pub const SSPxCON1 = packed struct {
    /// SSPM<3:0>: Master Synchronous Serial Port Mode Select bits.
    /// 1010 = SPI Master mode: clock = Fosc/8.
    /// 0101 = SPI Slave mode: clock = SCKx pin; SSx pin control disabled; SSx can be used as I/O pin.
    /// 0100 = SPI Slave mode: clock = SCKx pin; SSx pin control enabled.
    /// 0011 = SPI Master mode: clock = TMR2 output/2.
    /// 0010 = SPI Master mode: clock = Fosc/64.
    /// 0001 = SPI Master mode: clock = Fosc/16.
    /// 0000 = SPI Master mode: clock = Fosc/4.
    SSPM: u4,
    /// CKP: Clock Polarity Select bit.
    /// 1 = Idle state for the clock is a high level.
    /// 0 = Idle state for the clock is a low level.
    CKP: u1,
    /// SSPEN: Master Synchronous Serial Port Enable bit.
    /// 1 = Enables serial port and configures SCKx, SDOx, SDIx and SSx as serial port pins.
    /// 0 = Disables serial port and configures these pins as I/O port pins.
    SSPEN: u1,
    /// SSPOV: Receive Overflow Indicator bit.
    /// SPI Slave mode: 1 = A new byte is received while SSPxBUF is still holding the previous data
    ///                     (must be cleared in software).
    ///                 0 = No overflow.
    SSPOV: u1,
    /// WCOL: Write Collision Detect bit.
    /// 1 = The SSPxBUF register is written while it is still transmitting the previous word
    ///     (must be cleared in software).
    /// 0 = No collision.
    WCOL: u1,
};

pub const PICMSSP = struct {
    BUF_REG_HANDLER: SpecialFunctionRegisterHandler,
    ADD_REG_HANDLER: SpecialFunctionRegisterHandler,
    STAT_REG_HANDLER: SpecialFunctionRegisterHandler,
    CON1_REG_HANDLER: SpecialFunctionRegisterHandler,
    CON2_REG_HANDLER: SpecialFunctionRegisterHandler,

    stat_reg: SSPxSTAT,
    con1_reg: SSPxCON1,

    pub fn init() PICMSSP {
        return PICMSSP{
            .BUF_REG_HANDLER = .{
                .vtable = &.{
                    .read = bufRead,
                    .write = bufWrite,
                },
            },
            .ADD_REG_HANDLER = .{
                .vtable = &.{
                    .read = addRead,
                    .write = addWrite,
                },
            },
            .STAT_REG_HANDLER = .{
                .vtable = &.{
                    .read = statRead,
                    .write = statWrite,
                },
            },
            .CON1_REG_HANDLER = .{
                .vtable = &.{
                    .read = con1Read,
                    .write = con1Write,
                },
            },
            .CON2_REG_HANDLER = .{
                .vtable = &.{
                    .read = con2Read,
                    .write = con2Write,
                },
            },

            .stat_reg = @bitCast(@as(u8, 0)),
            .con1_reg = @bitCast(@as(u8, 0)),
        };
    }

    fn bufRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        var self = @as(*PICMSSP, @alignCast(@fieldParentPtr("BUF_REG_HANDLER", handler)));
        std.debug.print("MSSP BUF read\n", .{});
        self.stat_reg.BF = 0;
        return 0;
    }

    fn bufWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self = @as(*PICMSSP, @alignCast(@fieldParentPtr("BUF_REG_HANDLER", handler)));
        std.debug.print("MSSP BUF write 0x{x}\n", .{value});
        // pic.MEM[addr] = value;
        self.stat_reg.BF = 1;
    }

    fn addRead(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        _ = @as(*PICMSSP, @alignCast(@fieldParentPtr("ADD_REG_HANDLER", handler)));
        std.debug.print("MSSP ADD read\n", .{});
        return pic.MEM[addr];
    }

    fn addWrite(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        _ = @as(*PICMSSP, @alignCast(@fieldParentPtr("ADD_REG_HANDLER", handler)));
        std.debug.print("MSSP ADD write 0x{x}\n", .{value});
        pic.MEM[addr] = value;
    }

    fn statRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        var self = @as(*PICMSSP, @alignCast(@fieldParentPtr("STAT_REG_HANDLER", handler)));

        return (@as(*u8, @ptrCast(&self.stat_reg))).*; // Return the value of the STAT register instead of memory
    }

    fn statWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self = @as(*PICMSSP, @alignCast(@fieldParentPtr("STAT_REG_HANDLER", handler)));
        const WRITABLE_BITS: u8 = 0b11000000;
        std.debug.print("MSSP STAT write {}", .{value});
        self.stat_reg = @bitCast(value & WRITABLE_BITS | (@as(u8, @bitCast(self.stat_reg)) & ~WRITABLE_BITS));
    }

    fn con1Read(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        _ = @as(*PICMSSP, @alignCast(@fieldParentPtr("CON1_REG_HANDLER", handler)));
        std.debug.print("MSSP CON1 read\n", .{});
        return pic.MEM[addr];
    }

    fn con1Write(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        _ = @as(*PICMSSP, @alignCast(@fieldParentPtr("CON1_REG_HANDLER", handler)));
        std.debug.print("MSSP CON1 write 0x{x}\n", .{value});
        pic.MEM[addr] = value;
    }

    fn con2Read(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        _ = @as(*PICMSSP, @alignCast(@fieldParentPtr("CON2_REG_HANDLER", handler)));
        std.debug.print("MSSP CON2 read\n", .{});
        return pic.MEM[addr];
    }

    fn con2Write(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        _ = @as(*PICMSSP, @alignCast(@fieldParentPtr("CON2_REG_HANDLER", handler)));
        std.debug.print("MSSP CON2 write 0x{x}\n", .{value});
        pic.MEM[addr] = value;
    }
};
