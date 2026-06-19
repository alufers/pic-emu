const std = @import("std");
const pic18 = @import("pic18.zig");
const SpecialFunctionRegisterHandler = pic18.SpecialFunctionRegisterHandler;
const PIC18 = pic18.PIC18;
const PeripheralError = pic18.PeripheralError;

/// Implements a rudimentary EEPROM peripheral
/// For now it just returns FREE=1 in EECON1 so that code waiting for that bit passes through
pub const PICEeprom = struct {
    const Self = @This();

    const EECON1 = packed struct {
        /// Read Control bit
        RD: u1,

        /// Write control bit
        WR: u1,

        /// Flash Program/Data EEPROM Write Enable bit
        WREN: u1,

        /// Flash Program/Data EEPROM Error Flag bit
        WRERR: u1,

        /// Flash Row Erase Enable bit
        FREE: u1,

        /// Unimplemented
        unused: u1,

        /// Flash Program/Data EEPROM or Configuration Select bit
        CFGS: u1,

        /// Selects between flash Program or Data EEPROM Memory
        EEPGD: u1,
    };

    EECON1_REG_HANDLER: SpecialFunctionRegisterHandler,

    eecon1_reg: EECON1,

    pub fn init() PICEeprom {
        return PICEeprom{
            .EECON1_REG_HANDLER = .{
                .vtable = &.{
                    .read = Self.onEecon1Read,
                    .write = Self.onEecon1Write,
                },
            },
            .eecon1_reg = @bitCast(@as(u8, 0)),
        };
    }

    fn onEecon1Read(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16) PeripheralError!u8 {
        var self = @as(*Self, @alignCast(@fieldParentPtr("EECON1_REG_HANDLER", handler)));
        self.eecon1_reg.FREE = 1;
        return (@as(*u8, @ptrCast(&self.eecon1_reg))).*;
    }

    fn onEecon1Write(handler: *SpecialFunctionRegisterHandler, _: *PIC18, _: u16, value: u8) PeripheralError!void {
        var self = @as(*Self, @alignCast(@fieldParentPtr("EECON1_REG_HANDLER", handler)));

        self.eecon1_reg = @bitCast(value);
    }
};
