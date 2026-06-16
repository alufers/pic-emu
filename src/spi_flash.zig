const std = @import("std");
const spi_slave = @import("spi_slave.zig");

pub const SPIFlash = struct {
    const Self = @This();

    const State = enum {
        idle,
        write_status_register_1,
        read_status_register_1,
    };

    pub const StatusRegister1 = packed struct {
        BUSY: u1,
        WEL: u1,
        BP0: u1,
        BP1: u1,
        BP2: u1,
        TB: u1,
        SEC: u1,
        SRP: u1,
    };

    state: State,

    statusRegister1: StatusRegister1,

    spiSlaveInterface: spi_slave.SPISlave,

    pub fn init() Self {
        return .{
            .spiSlaveInterface = .{
                .vtable = &.{
                    .transact = Self.onTransact,
                },
            },
            .state = .idle,
            .statusRegister1 = @bitCast(@as(u8, 0)),
        };
    }

    pub fn onTransact(slave: *spi_slave.SPISlave, in: u8) u8 {
        const self: *Self = @alignCast(@fieldParentPtr("spiSlaveInterface", slave));
        switch (self.state) {
            .idle => {

                // Accept command
                switch (in) {
                    0x01 => { // Write Status Register-1
                        self.state = .write_status_register_1;
                        std.debug.print("[FLASH] Write Status Register-1\n", .{});
                    },
                    0x05 => { // Read Status Register-1
                        self.state = .read_status_register_1;
                        std.debug.print("[FLASH] Read Status Register-1\n", .{});
                    },
                    0x06 => { // Write Enable
                        std.debug.print("[FLASH] Write Enable\n", .{});
                        self.statusRegister1.WEL = 1;
                    },
                    0x50 => { // Write Enable for Volatile Status Register
                        std.debug.print("[FLASH] Write Enable for Volatile Status Register\n", .{});
                    },
                    else => {
                        // std.debug.print("[FLASH] UNKNOWN SPI FLASH COMMAND: 0x{x}\n", .{in});
                    },
                }
            },
            .write_status_register_1 => {
                self.statusRegister1 = @as(StatusRegister1, @bitCast(in));
                self.state = .idle;
            },
            .read_status_register_1 => {
                self.state = .idle;
                return @as(u8, @bitCast(self.statusRegister1));
            },
        }

        return 0;
    }
};
