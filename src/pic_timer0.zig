const std = @import("std");
const pic18 = @import("pic18.zig");
const SpecialFunctionRegisterHandler = pic18.SpecialFunctionRegisterHandler;
const PIC18 = pic18.PIC18;
const PeripheralError = pic18.PeripheralError;

pub const T0CON = packed struct {
    /// T0PS<2:0>: Timer0 Prescaler Select bits.
    /// 111 = 1:256 Prescale value
    /// 110 = 1:128 Prescale value
    /// 101 = 1:64 Prescale value
    /// 100 = 1:32 Prescale value
    /// 011 = 1:16 Prescale value
    /// 010 = 1:8 Prescale value
    /// 001 = 1:4 Prescale value
    /// 000 = 1:2 Prescale value
    T0PS: u3,
    /// PSA: Timer0 Prescaler Assignment bit.
    /// 1 = Timer0 prescaler is not assigned; Timer0 clock input bypasses prescaler.
    /// 0 = Timer0 prescaler is assigned; Timer0 clock input comes from prescaler output.
    PSA: u1,
    /// T0SE: Timer0 Source Edge Select bit.
    /// 1 = Increment on high-to-low transition on T0CKI pin.
    /// 0 = Increment on low-to-high transition on T0CKI pin.
    T0SE: u1,
    /// T0CS: Timer0 Clock Source Select bit.
    /// 1 = Transition on T0CKI pin input edge.
    /// 0 = Internal clock (FOSC/4).
    T0CS: u1,
    /// T08BIT: Timer0 8-Bit/16-Bit Control bit.
    /// 1 = Timer0 is configured as an 8-bit timer/counter.
    /// 0 = Timer0 is configured as a 16-bit timer/counter.
    T08BIT: u1,
    /// TMR0ON: Timer0 On/Off Control bit.
    /// 1 = Enables Timer0.
    /// 0 = Stops Timer0.
    TMR0ON: u1,
};

pub const PICTimer0 = struct {
    T0CON_REG_HANDLER: SpecialFunctionRegisterHandler,
    TMR0H_REG_HANDLER: SpecialFunctionRegisterHandler,
    TMR0L_REG_HANDLER: SpecialFunctionRegisterHandler,

    t0con: T0CON,

    timer_value: u16,

    pub fn init() PICTimer0 {
        return PICTimer0{
            .T0CON_REG_HANDLER = .{
                .vtable = &.{
                    .reset = t0conReset,
                    .read = t0conRead,
                    .write = t0conWrite,
                },
            },
            .TMR0H_REG_HANDLER = .{
                .vtable = &.{
                    .read = tmr0hRead,
                    .write = tmr0hWrite,
                },
            },
            .TMR0L_REG_HANDLER = .{
                .vtable = &.{
                    .read = tmr0lRead,
                    .write = tmr0lWrite,
                },
            },
            .t0con = @bitCast(@as(u8, 0xFF)), // POR value: 0xFF
            .timer_value = 0,
        };
    }

    pub fn tick(self: *PICTimer0, pic: *PIC18) void {
        if (self.t0con.TMR0ON == 1) {
            self.timer_value, _ = @addWithOverflow(self.timer_value, 1);
            if (self.t0con.T08BIT == 1 and self.timer_value == 256) {
                self.timer_value = 0;
            }
            if (self.timer_value == 0) {
                if (pic.REGS.INTCON.GIE == 1 and pic.REGS.INTCON.TMR0IE == 1) {
                    // std.debug.print("Timer0 FIRED!!!!!!!! INTCON = {}\n", .{pic.REGS.INTCON});
                    pic.STACK[pic.REGS.STKPTR.*] = pic.PC;
                    pic.REGS.STKPTR.* += 1;
                    pic.saveToShadow();
                    pic.REGS.INTCON.GIE = 0;
                    pic.REGS.INTCON.TMR0IF = 1;
                    pic.PC = 0x0008;
                }
            }
        }
    }

    fn t0conReset(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) void {
        var self: *PICTimer0 = @alignCast(@fieldParentPtr("T0CON_REG_HANDLER", handler));
        self.t0con = @bitCast(@as(u8, 0xFF));
    }

    fn t0conRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        const self: *PICTimer0 = @alignCast(@fieldParentPtr("T0CON_REG_HANDLER", handler));
        return @as(*const u8, @ptrCast(&self.t0con)).*;
    }

    fn t0conWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self: *PICTimer0 = @alignCast(@fieldParentPtr("T0CON_REG_HANDLER", handler));
        self.t0con = @bitCast(value);
        // std.debug.print("Timer0 T0CON write 0x{}\n", .{self.t0con});
    }

    fn tmr0hRead(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        _ = @as(*PICTimer0, @alignCast(@fieldParentPtr("TMR0H_REG_HANDLER", handler)));
        return pic.MEM[addr];
    }

    fn tmr0hWrite(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        _ = @as(*PICTimer0, @alignCast(@fieldParentPtr("TMR0H_REG_HANDLER", handler)));
        // std.debug.print("Timer0 TMR0H write 0x{x}\n", .{value});
        pic.MEM[addr] = value;
    }

    fn tmr0lRead(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16) PeripheralError!u8 {
        _ = @as(*PICTimer0, @alignCast(@fieldParentPtr("TMR0L_REG_HANDLER", handler)));
        return pic.MEM[addr];
    }

    fn tmr0lWrite(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, addr: u16, value: u8) PeripheralError!void {
        _ = @as(*PICTimer0, @alignCast(@fieldParentPtr("TMR0L_REG_HANDLER", handler)));
        // std.debug.print("Timer0 TMR0L write 0x{x}\n", .{value});
        pic.MEM[addr] = value;
    }
};
