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
        memory_access_control, // mac
    };

    const WIDTH = 240;
    const HEIGHT = 320;
    /// Integer upscaling factor for the on-screen window.
    const SCALE = 1;

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
    dataIdx: u64, // which parameter are we on

    columnStart: u16, // SC[15:0] in datasheet
    columnEnd: u16, // EC[15:0] in datasheet
    rowStart: u16, // SP[15:0] in datasheet
    rowEnd: u16, // EP[15:0] in datasheet

    xReg: u16,
    yReg: u16,

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
        disp.allocator = allocator;
        disp.prevWrValue = true;
        disp.isData = false;
        disp.pic = pic;
        disp.state = .idle;
        disp.columnStart = 0;
        disp.columnEnd = 0;
        disp.rowStart = 0;
        disp.rowEnd = 0;
        disp.dataIdx = 0;
        disp.xReg = 0;
        disp.yReg = 0;

        _ = try std.Thread.spawn(.{}, Self.drawThread, .{disp});

        return disp;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    fn drawThread(self: *Self) void {
        rl.initWindow(Self.WIDTH * Self.SCALE, Self.HEIGHT * Self.SCALE, "pic-emu");
        defer rl.closeWindow();

        rl.setTargetFPS(60);

        // Row-major RGB565 staging buffer matching a WIDTH x HEIGHT image. The
        // framebuffer is stored column-major ([x][y]), so it has to be
        // transposed before it can be uploaded to the GPU as an image.
        var pixels: [HEIGHT][WIDTH]u16 = undefined;

        const image = rl.Image{
            .data = @ptrCast(&pixels),
            .width = WIDTH,
            .height = HEIGHT,
            .mipmaps = 1,
            .format = .uncompressed_r5g6b5,
        };

        const texture = rl.loadTextureFromImage(image) catch |err| {
            std.debug.print("[DISP] failed to create texture: {}\n", .{err});
            return;
        };
        defer rl.unloadTexture(texture);

        while (!rl.windowShouldClose()) { // Detect window close button or ESC key
            // Transpose framebuffer[x][y] -> pixels[y][x].
            for (0..WIDTH) |x| {
                for (0..HEIGHT) |y| {
                    pixels[y][x] = self.framebuffer[x][y];
                }
            }
            rl.updateTexture(texture, &pixels);

            rl.beginDrawing();
            defer rl.endDrawing();

            rl.clearBackground(.black);
            rl.drawTextureEx(texture, .{ .x = 0, .y = 0 }, 0, @as(f32, Self.SCALE), .white);
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
                    std.debug.print("[DISP] set set_column_address START={} END={}\n", .{ self.columnStart, self.columnEnd });
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
                    std.debug.print("[DISP] set set_row_address START={} END={}\n", .{ self.rowStart, self.rowEnd });
                    self.state = .idle;
                }
                self.dataIdx += 1;
            },
            .write_gram => {
                if (self.xReg >= Self.WIDTH or self.yReg >= Self.HEIGHT) {
                    std.debug.print("[DISP] !!OOB!!  ROW_START={} ROW_END={} COL_START={} COL_END={}, X={}, Y={} \n", .{
                        self.columnStart,
                        self.columnEnd,
                        self.rowStart,
                        self.rowEnd,
                        self.xReg,
                        self.yReg,
                    });

                    self.pic.printStackTrace();
                    return;
                }

                const pixel: *[2]u8 = @ptrCast(@alignCast(&self.framebuffer[self.xReg][self.yReg]));
                pixel[(self.dataIdx + 1) % 2] = dat;

                self.dataIdx += 1;
                if (self.dataIdx == 2) {
                    self.dataIdx = 0;
                    self.xReg += 1;
                    if (self.xReg == self.columnEnd) {
                        self.xReg = self.columnStart;
                        self.yReg += 1;
                        if (self.yReg >= self.rowEnd) {
                            self.yReg = self.rowStart;
                        }
                    }
                }
            },
            .memory_access_control => {
                std.debug.print("[DISP] mac = 0x{x}\n", .{dat});
                self.state = .idle;
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
                self.xReg = self.columnStart;
                self.yReg = self.rowStart;
            },
            .mac => {
                self.state = .memory_access_control;
                self.dataIdx = 0;
            },
            else => {
                std.debug.print("[DISP] Got unhandled command {} (0x{x})\n", .{ cmd, @intFromEnum(cmd) });
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
