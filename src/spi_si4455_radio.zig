const std = @import("std");
const spi_slave = @import("spi_slave.zig");
const gpio = @import("gpio.zig");
const pic18 = @import("pic18.zig");

pub const SPISi4455Radio = struct {
    const Self = @This();

    const State = enum {
        idle,
        respond_READ_CMD_BUFF,
    };

    pub const Instruction = enum(u8) {
        READ_CMD_BUFF = 0x44,
        _,
    };

    pic: *pic18.PIC18,

    spiSlaveInterface: spi_slave.SPISlave,
    csPinInterface: gpio.GPIOPin,

    // State  + registers
    csPinState: bool,
    state: State,

    pub fn init(pic: *pic18.PIC18) Self {
        // flashBuf[0x10000] = 0x00; // force mismatch
        return .{
            .pic = pic,
            .spiSlaveInterface = .{
                .vtable = &.{
                    .transact = Self.onTransact,
                },
            },
            .csPinInterface = .{
                .vtable = &.{
                    .setMode = gpio.nopSetMode,
                    .read = Self.onCsRead,
                    .write = Self.onCsWrite,
                },
            },
            .csPinState = false,
            .state = .idle,
        };
    }

    fn onCsRead(pin: *gpio.GPIOPin) bool {
        const self: *Self = @fieldParentPtr("csPinInterface", pin);
        return self.csPinState;
    }

    fn onCsWrite(pin: *gpio.GPIOPin, val: bool) void {
        const self: *Self = @fieldParentPtr("csPinInterface", pin);
        if (self.csPinState != val and val == false) { // CS pin going low means new command will be sent
            self.state = .idle;
        }
        self.csPinState = val;
    }

    pub fn onTransact(slave: *spi_slave.SPISlave, in: u8) u8 {
        const self: *Self = @alignCast(@fieldParentPtr("spiSlaveInterface", slave));
        switch (self.state) {
            .idle => {
                const cmd: Instruction = @enumFromInt(in);
                // Accept command
                switch (cmd) {
                    .READ_CMD_BUFF => {
                        self.state = .respond_READ_CMD_BUFF;
                        return 0x00;
                    },
                    else => {
                        // std.debug.print("[RADIO] UNKNOWN RADIO COMMAND: 0x{x}\n", .{in});
                        // self.pic.printStackTrace();
                    },
                }
            },
            .respond_READ_CMD_BUFF => {
                self.state = .idle;
                return 0xFF;
            },
        }

        return 0;
    }
};
