const std = @import("std");
const pic18 = @import("pic18.zig");
const SpecialFunctionRegisterHandler = pic18.SpecialFunctionRegisterHandler;
const PIC18 = pic18.PIC18;
const PeripheralError = pic18.PeripheralError;

pub const RTCCFG = packed struct {
    /// Points to the corresponding RTCC Value registers when reading the RTCVALH and RTCVALL
    /// registers. The RTCPTR<1:0> value decrements on every read or write of RTCVALH<15:8> until it
    /// reaches ‘00’.
    RTCPTR: u2,

    /// RTCC Output Enable bit
    RTCOE: u1,

    /// Helf-Second status bit
    HALFSEC: u1,

    /// RTCC Value Registers Read Synchronization bit
    RTCSYNC: u1,

    /// RTCC Value Registers Write Enable bit
    RTCWREN: u1,

    unimplemented: u1,

    /// RTCEN: RTCC Enable bit
    RTCEN: u1,
};

pub const PICRTCC = struct {
    const Self = @This();

    RTCCFG_REG_HANDLER: SpecialFunctionRegisterHandler,
    RTCVALH_REG_HANDLER: SpecialFunctionRegisterHandler,
    RTCVALL_REG_HANDLER: SpecialFunctionRegisterHandler,

    rtccfg: RTCCFG,

    year: u8,
    month: u8,
    day: u8,
    weekday: u8,
    hour: u8,
    minute: u8,
    second: u8,

    pub fn init() Self {
        return Self{
            .RTCCFG_REG_HANDLER = .{
                .vtable = &.{
                    .reset = rtccfgReset,
                    .read = rtccfgRead,
                    .write = rtccfgWrite,
                },
            },
            .RTCVALH_REG_HANDLER = .{
                .vtable = &.{
                    .read = rtcvalhRead,
                    .write = rtcvalhWrite,
                },
            },
            .RTCVALL_REG_HANDLER = .{
                .vtable = &.{
                    .read = rtcvallRead,
                    .write = rtcvallWrite,
                },
            },

            .rtccfg = @bitCast(@as(u8, 0x00)), // POR value: 0x00

            .year = 26,
            .month = 8,
            .day = 26,
            .weekday = 3,
            .hour = 0,
            .minute = 0,
            .second = 0,
        };
    }

    pub fn tick(self: *Self, pic: *PIC18) void {
        _ = self;
        _ = pic;
    }

    fn rtccfgReset(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) void {
        var self: *Self = @alignCast(@fieldParentPtr("RTCCFG_REG_HANDLER", handler));
        self.rtccfg = @bitCast(@as(u8, 0x00));
    }

    fn rtccfgRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        const self: *Self = @alignCast(@fieldParentPtr("RTCCFG_REG_HANDLER", handler));
        return @as(*const u8, @ptrCast(&self.rtccfg)).*;
    }

    fn rtccfgWrite(handler: *SpecialFunctionRegisterHandler, pic: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self: *Self = @alignCast(@fieldParentPtr("RTCCFG_REG_HANDLER", handler));

        const writeMask: u8 = @bitCast(if (self.rtccfg.RTCWREN == 1) RTCCFG{
            .RTCWREN = 1,
            .RTCEN = 1,
            .RTCPTR = 0b11,
            .RTCOE = 0b1,
            .HALFSEC = 0,
            .RTCSYNC = 0,
            .unimplemented = 0,
        } else RTCCFG{
            .RTCWREN = 1,
            .RTCPTR = 0b11,
            .RTCOE = 0b1,
            .RTCEN = 0,
            .HALFSEC = 0,
            .RTCSYNC = 0,
            .unimplemented = 0,
        });

        const origValue = @as(u8, @bitCast(self.rtccfg)) & (~@as(u8, @bitCast(writeMask)));

        self.rtccfg = @bitCast((value & writeMask) | origValue);
        std.debug.print("RTCC RTCCFG write 0x{}\n", .{self.rtccfg});

        pic.printStackTrace();
    }

    fn rtcvalhRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        const self: *Self = @alignCast(@fieldParentPtr("RTCVALH_REG_HANDLER", handler));
        defer self.rtccfg.RTCPTR -|= 1; //  The RTCPTR<1:0> value decrements on every read or write of RTCVALH<15:8> until it reaches 00.
        switch (self.rtccfg.RTCPTR) {
            0b00 => { // minutes
                return toBCD(self.minute);
            },
            0b01 => { // weekday
                return toBCD(self.weekday);
            },
            0b10 => { // month
                return toBCD(self.month);
            },
            0b11 => { // reserved
                return 0;
            },
        }
    }

    fn rtcvalhWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self: *Self = @alignCast(@fieldParentPtr("RTCVALH_REG_HANDLER", handler));
        if (self.rtccfg.RTCWREN == 0) return;
        defer self.rtccfg.RTCPTR -|= 1; // TODO: should this be before the previous condition?
        switch (self.rtccfg.RTCPTR) {
            0b00 => { // minutes
                self.minute = fromBCD(value);
            },
            0b01 => { // weekday
                self.weekday = fromBCD(value);
            },
            0b10 => { // month
                self.month = fromBCD(value);
            },
            0b11 => { // reserved
                return;
            },
        }
    }

    fn rtcvallRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        const self: *Self = @alignCast(@fieldParentPtr("RTCVALL_REG_HANDLER", handler));
        switch (self.rtccfg.RTCPTR) {
            0b00 => { // seconds
                return toBCD(self.second);
            },
            0b01 => { // hours
                return toBCD(self.hour);
            },
            0b10 => { // day
                return toBCD(self.day);
            },
            0b11 => { // year
                return toBCD(self.year);
            },
        }
    }

    fn rtcvallWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self: *Self = @alignCast(@fieldParentPtr("RTCVALL_REG_HANDLER", handler));
        if (self.rtccfg.RTCWREN == 0) return;
        switch (self.rtccfg.RTCPTR) {
            0b00 => { // seconds
                self.second = fromBCD(value);
            },
            0b01 => { // hours
                self.hour = fromBCD(value);
            },
            0b10 => { // day
                self.day = fromBCD(value);
            },
            0b11 => { // year
                self.year = fromBCD(value);
            },
        }
    }

    fn toBCD(val: u8) u8 {
        std.debug.assert(val <= 99);

        return ((val / 10) << 4) | (val % 10);
    }

    fn fromBCD(val: u8) u8 {
        return (((val & 0xF0) >> 4) * 10) + (val & 0x0F);
    }
};

test "bcd test" {
    for (0..99) |idx| {
        try std.testing.expectEqual(PICRTCC.fromBCD(PICRTCC.toBCD(@intCast(idx))), idx);
    }
}
