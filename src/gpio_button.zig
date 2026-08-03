const std = @import("std");
const gpio = @import("gpio.zig");
const ui = @import("ui.zig");
const pic18 = @import("pic18.zig");

pub const GPIOButton = struct {
    const Self = @This();

    pic: *pic18.PIC18,
    pinInterface: gpio.GPIOPin,
    ui_iface: *ui.UI,
    key: ui.Key,

    pub fn init(pic: *pic18.PIC18, ui_iface: *ui.UI, key: ui.Key) Self {
        return Self{
            .pic = pic,
            .ui_iface = ui_iface,
            .key = key,
            .pinInterface = .{
                .vtable = &.{
                    .setMode = gpio.nopSetMode,
                    .write = gpio.nopWrite,
                    .read = Self.onPinRead,
                },
            },
        };
    }

    pub fn fireInterruptIfNeeded(self: *Self) void {
        if (self.ui_iface.isKeyPressed(self.key)) {
            std.debug.print("[BUTTON] FIRING ISR", .{});
            self.pic.handleInterrupt();
        }
    }

    pub fn onPinRead(pin: *gpio.GPIOPin) bool {
        const self: *Self = @fieldParentPtr("pinInterface", pin);

        return !self.ui_iface.isKeyDown(self.key); // low level active
    }
};
