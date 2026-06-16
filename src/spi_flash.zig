const std = @import("std");
const spi_slave = @import("spi_slave.zig");
const gpio = @import("gpio.zig");
const pic18 = @import("pic18.zig");

pub const SPIFlash = struct {
    const Self = @This();

    const State = enum {
        idle,
        write_status_register_1,
        read_status_register_1,

        fast_read_receive_addr, // Address receive from MCU for the read
        fast_read_data, // Send data to the MCU in this state
    };

    pub const Instruction = enum(u8) {
        write_status_register_1 = 0x01,
        read_status_register_1 = 0x05,
        write_enable = 0x06,
        write_enable_volatile_status_register = 0x50,
        fast_read = 0x0b,
        _,
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

    pic: *pic18.PIC18,

    spiSlaveInterface: spi_slave.SPISlave,
    csPinInterface: gpio.GPIOPin,

    // State  + registers
    csPinState: bool,
    state: State,
    statusRegister1: StatusRegister1,
    paramIdx: u64,
    addr: u24,
    flashBuf: []u8,

    pub fn init(pic: *pic18.PIC18, flashBuf: []u8) Self {
        flashBuf[0x10000] = 0x00; // force mismatch
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
            .statusRegister1 = @bitCast(@as(u8, 0)),
            .paramIdx = 0,
            .addr = 0,
            .flashBuf = flashBuf,
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
                    .write_status_register_1 => {
                        self.state = .write_status_register_1;
                        std.debug.print("[FLASH] Write Status Register-1\n", .{});
                    },
                    .read_status_register_1 => {
                        self.state = .read_status_register_1;
                        std.debug.print("[FLASH] Read Status Register-1\n", .{});
                    },
                    .write_enable => {
                        std.debug.print("[FLASH] Write Enable\n", .{});
                        self.statusRegister1.WEL = 1;
                    },
                    .write_enable_volatile_status_register => {
                        std.debug.print("[FLASH] Write Enable for Volatile Status Register\n", .{});
                    },
                    .fast_read => {
                        self.pic.printStackTrace();
                        self.paramIdx = 0;
                        self.state = .fast_read_receive_addr;
                        self.addr = 0;
                    },
                    else => {
                        std.debug.print("[FLASH] UNKNOWN SPI FLASH COMMAND: 0x{x}\n", .{in});
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
            .fast_read_receive_addr => {
                if (self.paramIdx < 3) {
                    self.addr = (self.addr & 0xFFFF00) | in;
                    if (self.paramIdx < 2) {
                        self.addr <<= 8;
                    }
                }
                self.paramIdx += 1;
                if (self.paramIdx == 4) { // allow for one dummy cycle
                    std.debug.print("[FLASH] FAST READ addr=0x{x}\n", .{self.addr});
                    self.state = .fast_read_data;
                }
            },
            .fast_read_data => {
                const dat = self.flashBuf[self.addr];
                // std.debug.print("[FLASH] Read data: 0x{x}\n", .{dat});
                self.addr += 1;
                return dat;
            },
        }

        return 0;
    }
};
