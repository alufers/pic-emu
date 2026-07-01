const std = @import("std");
const rl = @import("raylib");
const ui = @import("ui.zig");

pub const RaylibUI = struct {
    const Self = @This();

    pub const WIDTH = 240;
    pub const HEIGHT = 320;
    const SCALE = 1;

    const KEY_COUNT = @typeInfo(ui.Key).@"enum".fields.len;

    interface: ui.UI,
    allocator: std.mem.Allocator,
    thread: ?std.Thread,

    fbLock: std.atomic.Value(bool),
    /// RGB565
    framebuffer: [WIDTH][HEIGHT]u16,
    exitFlag: std.atomic.Value(bool),
    userExit: std.atomic.Value(bool),
    /// Level state: whether each key is currently held down (isKeyDown).
    keyDown: [KEY_COUNT]std.atomic.Value(bool),
    /// Edge latch: set by the draw thread when a key is first pressed,
    /// consumed (cleared) by isKeyPressed so a press is reported exactly once.
    keyPressLatch: [KEY_COUNT]std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .interface = .{
                .vtable = &.{
                    .setPixel = Self.onSetPixel,
                    .exitRequested = Self.onExitRequested,
                    .requestExit = Self.onRequestExit,
                    .isKeyPressed = Self.onIsKeyPressed,
                    .isKeyDown = Self.onIsKeyDown,
                },
            },
            .allocator = allocator,
            .thread = null,
            .fbLock = std.atomic.Value(bool).init(false),
            .framebuffer = std.mem.zeroes([WIDTH][HEIGHT]u16),
            .exitFlag = std.atomic.Value(bool).init(false),
            .userExit = std.atomic.Value(bool).init(false),
            .keyDown = [_]std.atomic.Value(bool){std.atomic.Value(bool).init(false)} ** KEY_COUNT,
            .keyPressLatch = [_]std.atomic.Value(bool){std.atomic.Value(bool).init(false)} ** KEY_COUNT,
        };

        self.thread = try std.Thread.spawn(.{}, Self.drawThread, .{self});

        return self;
    }

    fn lockFb(self: *Self) void {
        while (self.fbLock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlockFb(self: *Self) void {
        self.fbLock.store(false, .release);
    }

    pub fn deinit(self: *Self) void {
        self.exitFlag.store(true, .release);
        if (self.thread) |t| {
            t.join();
            self.thread = null;
        }
        self.allocator.destroy(self);
    }

    fn onSetPixel(iface: *ui.UI, x: u16, y: u16, color: u16) void {
        const self: *Self = @alignCast(@fieldParentPtr("interface", iface));
        if (x >= WIDTH or y >= HEIGHT) {
            return;
        }
        self.lockFb();
        defer self.unlockFb();
        self.framebuffer[x][y] = color;
    }

    fn onExitRequested(iface: *ui.UI) bool {
        const self: *Self = @alignCast(@fieldParentPtr("interface", iface));
        return self.userExit.load(.acquire);
    }

    fn onRequestExit(iface: *ui.UI) void {
        const self: *Self = @alignCast(@fieldParentPtr("interface", iface));
        self.exitFlag.store(true, .release);
    }

    /// Edge-triggered: returns true once per physical key press, then clears
    /// the latch so subsequent polls see false until the next press.
    fn onIsKeyPressed(iface: *ui.UI, key: ui.Key) bool {
        const self: *Self = @alignCast(@fieldParentPtr("interface", iface));
        return self.keyPressLatch[@intFromEnum(key)].swap(false, .acquire);
    }

    /// Level: whether the key is currently held down.
    fn onIsKeyDown(iface: *ui.UI, key: ui.Key) bool {
        const self: *Self = @alignCast(@fieldParentPtr("interface", iface));
        return self.keyDown[@intFromEnum(key)].load(.acquire);
    }

    fn mapKey(key: ui.Key) rl.KeyboardKey {
        return switch (key) {
            .left => .left,
            .right => .right,
            .up => .up,
            .down => .down,
            .enter => .enter,
            .one => .one,
            .two => .two,
            .three => .three,
        };
    }

    fn drawThread(self: *Self) void {
        rl.setTraceLogLevel(rl.TraceLogLevel.none);
        rl.initWindow(WIDTH * SCALE, HEIGHT * SCALE, "pic-emu");
        defer rl.closeWindow();

        rl.setTargetFPS(60);

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

        while (true) {
            if (self.exitFlag.load(.acquire)) {
                break;
            }
            if (rl.windowShouldClose()) { // Detect window close button or ESC key
                self.userExit.store(true, .release);
                break;
            }

            {
                self.lockFb();
                defer self.unlockFb();
                for (0..WIDTH) |x| {
                    for (0..HEIGHT) |y| {
                        pixels[y][x] = self.framebuffer[x][y];
                    }
                }
            }
            rl.updateTexture(texture, &pixels);

            {
                rl.beginDrawing();
                defer rl.endDrawing();

                rl.clearBackground(.black);
                rl.drawTextureEx(texture, .{ .x = 0, .y = 0 }, 0, @as(f32, SCALE), .white);
            }

            // Refresh key state for the emulator thread to poll: level state
            // for isKeyDown, plus latch fresh presses for isKeyPressed.
            inline for (std.meta.fields(ui.Key)) |field| {
                const key: ui.Key = @enumFromInt(field.value);
                self.keyDown[field.value].store(rl.isKeyDown(mapKey(key)), .release);
                if (rl.isKeyPressed(mapKey(key))) {
                    self.keyPressLatch[field.value].store(true, .release);
                }
            }
        }
    }
};
