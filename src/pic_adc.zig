const std = @import("std");
const pic18 = @import("pic18.zig");
const SpecialFunctionRegisterHandler = pic18.SpecialFunctionRegisterHandler;
const PIC18 = pic18.PIC18;
const PeripheralError = pic18.PeripheralError;

pub const PICAdc = struct {
    const Self = @This();

    const ADCON0 = packed struct {
        /// Controls whether adc is working
        ADON: u1,

        /// GO/~(DONE) - when set to 1 the ADC is working, the bit is cleared when conversion finishes
        GO_DONE: u1,

        /// Channel select bits
        CHS: u5,

        unimplemented: u1,
    };

    ADCON0_REG_HANDLER: SpecialFunctionRegisterHandler,
    adcon0_reg: ADCON0,

    ADRESH_REG_HANDLER: SpecialFunctionRegisterHandler,
    ADRESL_REG_HANDLER: SpecialFunctionRegisterHandler,

    adc_result: u16,

    pub fn init() Self {
        return Self{
            .ADCON0_REG_HANDLER = .{
                .vtable = &.{
                    .read = onAdcon0Read,
                    .write = onAdcon0Write,
                },
            },
            .ADRESH_REG_HANDLER = .{
                .vtable = &.{
                    .read = onAdreshRead,
                    .write = onAdreshWrite,
                },
            },
            .ADRESL_REG_HANDLER = .{
                .vtable = &.{
                    .read = onAdreslRead,
                    .write = onAdreslWrite,
                },
            },
            .adcon0_reg = @bitCast(@as(u8, 0)),
            .adc_result = 0,
        };
    }

    fn onAdcon0Read(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        var self = @as(*Self, @alignCast(@fieldParentPtr("ADCON0_REG_HANDLER", handler)));

        return (@as(*u8, @ptrCast(&self.adcon0_reg))).*;
    }

    fn onAdcon0Write(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self = @as(*Self, @alignCast(@fieldParentPtr("ADCON0_REG_HANDLER", handler)));

        self.adcon0_reg = @bitCast(value);
        self.adcon0_reg.unimplemented = 0;
    }

    fn onAdreshRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        const self = @as(*Self, @alignCast(@fieldParentPtr("ADCON0_REG_HANDLER", handler)));

        return @intCast((self.adc_result >> 8) & 0xFF);
    }

    fn onAdreshWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self = @as(*Self, @alignCast(@fieldParentPtr("ADCON0_REG_HANDLER", handler)));

        self.adc_result = (@as(u16, value) << 8) | (self.adc_result & 0xFF);
    }

    fn onAdreslRead(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        const self = @as(*Self, @alignCast(@fieldParentPtr("ADCON0_REG_HANDLER", handler)));

        return @intCast(self.adc_result & 0xFF);
    }

    fn onAdreslWrite(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self = @as(*Self, @alignCast(@fieldParentPtr("ADCON0_REG_HANDLER", handler)));

        self.adc_result = (self.adc_result & 0xFF00) | value;
    }

    pub fn tick(self: *Self, _: *PIC18) void {
        if (self.adcon0_reg.GO_DONE == 1) {
            self.adcon0_reg.GO_DONE = 0;
            self.adc_result = 65535;
        }
    }
};
