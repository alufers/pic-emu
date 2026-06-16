const std = @import("std");
const gpio = @import("gpio.zig");
const pic18 = @import("pic18.zig");
const rl = @import("raylib");
const LcdCommand = @import("ili9341_cmds.zig").LcdCommand;

pub const DisplayDataPin = struct {
    const Self = @This();

    interface: gpio.GPIOPin,
    val: bool,

    pub fn init() Self {
        return .{
            .interface = .{
                .vtable = &.{
                    .setMode = Self.onSetMode,
                    .read = Self.onRead,
                    .write = Self.onWrite,
                },
            },
            .val = false,
        };
    }

    fn onSetMode(_: *gpio.GPIOPin, _: gpio.GPIOMode) void {}

    fn onRead(pin: *gpio.GPIOPin) bool {
        const self: *Self = @alignCast(@fieldParentPtr("interface", pin));
        return self.val;
    }

    fn onWrite(pin: *gpio.GPIOPin, value: bool) void {
        const self: *Self = @alignCast(@fieldParentPtr("interface", pin));
        self.val = value;
    }
};

pub const ILI9341Display = struct {
    const Self = @This();

    const State = enum {
        idle,
        set_column_address,
        set_row_address,
        write_gram, // write into framebuffer
    };

    const WIDTH = 240;
    const HEIGHT = 320;

    allocator: std.mem.Allocator,
    pic: *pic18.PIC18,

    // MCU side interface

    dataPins: [8]DisplayDataPin,
    /// Data/Command pin interface
    dcPinInterface: gpio.GPIOPin,
    wrPinInterface: gpio.GPIOPin,
    /// State of the Data/Command pin
    isData: bool,
    prevWrValue: bool,

    // Registers
    state: State,
    dataIdx: u16, // which parameter are we on

    columnStart: u16, // SC[15:0] in datasheet
    columnEnd: u16, // EC[15:0] in datasheet
    rowStart: u16, // SP[15:0] in datasheet
    rowEnd: u16, // EP[15:0] in datasheet

    // Display side data
    framebuffer: [WIDTH][HEIGHT]u16,

    pub fn init(allocator: std.mem.Allocator, pic: *pic18.PIC18) !*Self {
        var disp = allocator.create(Self) catch unreachable;

        disp.dataPins = .{ DisplayDataPin.init(), DisplayDataPin.init(), DisplayDataPin.init(), DisplayDataPin.init(), DisplayDataPin.init(), DisplayDataPin.init(), DisplayDataPin.init(), DisplayDataPin.init() };
        disp.dcPinInterface = .{
            .vtable = &.{
                .setMode = gpio.nopSetMode,
                .read = Self.onDcPinRead,
                .write = Self.onDcPinWrite,
            },
        };
        disp.wrPinInterface = .{
            .vtable = &.{
                .setMode = gpio.nopSetMode,
                .read = gpio.nopRead,
                .write = Self.onWrPinWrite,
            },
        };
        disp.prevWrValue = true;
        disp.isData = false;
        disp.pic = pic;
        disp.state = .idle;
        disp.columnStart = 0;
        disp.columnEnd = 0;
        disp.rowStart = 0;
        disp.rowEnd = 0;
        disp.dataIdx = 0;

        _ = try std.Thread.spawn(.{}, Self.drawThread, .{disp});

        return disp;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn drawThread(_: *Self) void {
        rl.initWindow(Self.WIDTH, Self.HEIGHT, "pic-emu");
        defer rl.closeWindow();

        rl.setTargetFPS(60);

        while (!rl.windowShouldClose()) { // Detect window close button or ESC key

            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(.black);
        }
    }

    /// Combine data pin states into a byte
    fn collectData(self: *Self) u8 {
        var val: u8 = 0;
        for (0..8) |idx| {
            val |= (if (self.dataPins[idx].val) @as(u8, 1) else @as(u8, 0)) << @as(u3, @intCast(idx));
        }
        return val;
    }
    fn onWrPinWrite(pin: *gpio.GPIOPin, value: bool) void {
        const self: *Self = @alignCast(@fieldParentPtr("wrPinInterface", pin));
        if (value == self.prevWrValue) {
            return;
        }
        self.prevWrValue = value;
        if (!value) {
            return;
        }

        const dat = self.collectData();
        if (self.isData) {
            self.handleData(dat);
        } else {
            self.handleCommand(@enumFromInt(dat));
        }
    }

    fn handleData(self: *Self, dat: u8) void {
        switch (self.state) {
            .set_column_address => {
                // WTF is going on here...
                if (self.dataIdx < 2) {
                    const colStart: *[2]u8 = @ptrCast(@alignCast(&self.columnStart));
                    colStart[(self.dataIdx + 1) % 2] = dat;
                } else if (self.dataIdx < 4) {
                    const colEnd: *[2]u8 = @ptrCast(@alignCast(&self.columnEnd));
                    colEnd[(self.dataIdx - 2 + 1) % 2] = dat;
                }
                // std.debug.print("[DISP] DATA[{}] {} START={} END={}\n", .{ self.dataIdx, dat, self.columnStart, self.columnEnd });
                if (self.dataIdx >= 3) {
                    // std.debug.print("[DISP] set set_column_address START={} END={}\n", .{ self.columnStart, self.columnEnd });
                    self.state = .idle;
                }
                self.dataIdx += 1;
            },
            .set_row_address => {
                // WTF is going on here...
                if (self.dataIdx < 2) {
                    const rowStart: *[2]u8 = @ptrCast(@alignCast(&self.rowStart));
                    rowStart[(self.dataIdx + 1) % 2] = dat;
                } else if (self.dataIdx < 4) {
                    const rowEnd: *[2]u8 = @ptrCast(@alignCast(&self.rowEnd));
                    rowEnd[(self.dataIdx - 2 + 1) % 2] = dat;
                }

                if (self.dataIdx >= 3) {
                    self.state = .idle;
                }
                self.dataIdx += 1;
            },
            .write_gram => {
                std.debug.print("[DISP] ROW_START={} ROW_END={} COL_START={} COL_END={} \n", .{ self.columnStart, self.columnEnd, self.rowStart, self.rowEnd });
                const x = (self.dataIdx / 2) % (self.columnEnd - self.columnStart);
                const y = (self.dataIdx / 2) / (self.rowEnd - self.rowStart);

                std.debug.print("[DISP] memwrite, X={}, Y={}\n", .{ x, y });

                self.dataIdx +%= 1;

                const pixel: *[2]u8 = @ptrCast(@alignCast(&self.framebuffer[x][y]));
                pixel[self.dataIdx % 2] = dat;
            },
            else => {}, // NOP
        }
    }

    fn handleCommand(self: *Self, cmd: LcdCommand) void {
        switch (cmd) {
            .column_addr => {
                self.state = .set_column_address;
                self.dataIdx = 0;
            },
            .page_addr => {
                self.state = .set_row_address;
                self.dataIdx = 0;
            },
            .gram => {
                self.state = .write_gram;
                self.dataIdx = 0;
            },
            else => {
                std.debug.print("[DISP] Got unhandled command {}\n", .{cmd});
            },
        }
    }

    fn onDcPinWrite(pin: *gpio.GPIOPin, value: bool) void {
        const self: *Self = @alignCast(@fieldParentPtr("dcPinInterface", pin));
        // std.debug.print("[ILI9341] DC = {}, PC = 0x{x}\n", .{ value, self.pic.PC });
        self.isData = value;
    }

    fn onDcPinRead(pin: *gpio.GPIOPin) bool {
        const self: *Self = @alignCast(@fieldParentPtr("dcPinInterface", pin));
        // std.debug.print("READ {}, PC = 0x{x}\n", .{ self.isData, self.pic.PC });
        return self.isData;
    }
};
