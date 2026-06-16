const pic18 = @import("pic18.zig");
const SpecialFunctionRegisterHandler = pic18.SpecialFunctionRegisterHandler;
const PIC18 = pic18.PIC18;
const gpio = @import("gpio.zig");
const PeripheralError = pic18.PeripheralError;

pub const PICGPIOPort = struct {
    PORT_REG_HANDLER: SpecialFunctionRegisterHandler,
    TRIS_REG_HANDLER: SpecialFunctionRegisterHandler,
    LAT_REG_HANDLER: SpecialFunctionRegisterHandler,

    pins: [8]?*gpio.GPIOPin,

    pub fn init() PICGPIOPort {
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
        return result;
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
