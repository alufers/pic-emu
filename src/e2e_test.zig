const std = @import("std");
const main = @import("main.zig");
const test_utils = @import("test_utils.zig");
const gpio = @import("gpio.zig");
const asm2emu = test_utils.asm2emu;

test "copy program memory to RAM via TBLRD loop" {
    var pic = try asm2emu(
        \\      MOVLW LOW(src)
        \\      MOVWF TBLPTRL, 0
        \\      MOVLW HIGH(src)
        \\      MOVWF TBLPTRH, 0
        \\      MOVLW UPPER(src)
        \\      MOVWF TBLPTRU, 0
        \\      LFSR 0, 0x200
        \\      LFSR 1, 4
        \\loop:
        \\      TBLRD *+
        \\      MOVFF TABLAT, POSTINC0
        \\      MOVF POSTDEC1, 0, 0
        \\      MOVF FSR1L, 0, 0
        \\      BNZ loop
        \\      ORG 0x100
        \\src:
        \\      DB 0x11, 0x22, 0x33, 0x44
        \\  END
    );
    defer pic.deinit();

    for (0..28) |_| {
        // Print FSR0
        try pic.execInstruction();
    }

    try std.testing.expectEqual(0x11, pic.MEM[0x200]);
    try std.testing.expectEqual(0x22, pic.MEM[0x201]);
    try std.testing.expectEqual(0x33, pic.MEM[0x202]);
    try std.testing.expectEqual(0x44, pic.MEM[0x203]);
}

test "clear GPIO register" {
    var pic = try asm2emu(
        \\      CLRF PORTA, 0
        \\  END
    );
    defer pic.deinit();

    try pic.execInstruction();
}

test "writes GPIO pin" {
    var pic = try asm2emu(
        \\      CLRF PORTA, 0
        \\      BSF PORTA, 3
        \\  END
    );
    defer pic.deinit();

    const TestingGPIOPin = struct {
        const Self = @This();

        val: bool = false,
        vtable: gpio.GPIOPinVtable,

        pub fn init() Self {
            return Self{
                .vtable = gpio.GPIOPinVtable{
                    .write = Self.onWrite,
                    .setMode = gpio.NOPGPIOPin.setMode,
                    .read = gpio.NOPGPIOPin.read,
                },
            };
        }

        fn onWrite(vtab: *gpio.GPIOPinVtable, val: bool) void {
            const self: *Self = @fieldParentPtr("vtable", vtab);
            self.val = val;
        }
    };

    var pin_handler = TestingGPIOPin.init();
    pic.GPIOPortA.pins[3] = &pin_handler.vtable;

    try pic.execInstruction();
    try pic.execInstruction();

    try std.testing.expectEqual(true, pin_handler.val);
}
