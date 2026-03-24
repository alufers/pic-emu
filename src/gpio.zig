const std = @import("std");

// GPIO Interface description

pub const GPIOMode = enum {
    Input,
    Output,
};

pub const GPIOPin = struct {
    const VTable = struct {
        setMode: *const fn (self: *GPIOPin, mode: GPIOMode) void,
        read: *const fn (self: *GPIOPin) bool,
        write: *const fn (self: *GPIOPin, value: bool) void,
    };
    vtable: *const VTable,

    pub fn setMode(self: *GPIOPin, mode: GPIOMode) void {
        self.vtable.setMode(self, mode);
    }

    pub fn read(self: *GPIOPin) bool {
        return self.vtable.read(self);
    }

    pub fn write(self: *GPIOPin, value: bool) void {
        self.vtable.write(self, value);
    }
};

fn nopSetMode(_: *GPIOPin, _: GPIOMode) void {}

fn nopRead(_: *GPIOPin) bool {
    return false;
}

fn nopWrite(_: *GPIOPin, _: bool) void {}

pub const NOPGPIOPin: GPIOPin = .{
    .vtable = &.{
        .setMode = nopSetMode,
        .read = nopRead,
        .write = nopWrite,
    },
};

pub const LoggingGPIOPin = struct {
    const Self = @This();

    interface: GPIOPin,
    name: []const u8,
    lastValue: ?bool = null,
    lastMode: ?GPIOMode = null,

    pub fn init(name: []const u8) Self {
        return .{
            .interface = .{
                .vtable = &.{
                    .setMode = Self.onSetMode,
                    .read = Self.onRead,
                    .write = Self.onWrite,
                },
            },
            .name = name,
        };
    }

    fn onSetMode(pin: *GPIOPin, mode: GPIOMode) void {
        const self: *Self = @fieldParentPtr("interface", pin);
        if (self.lastMode) |last| {
            if (last == mode) {
                return;
            }
        }
        std.debug.print("[[[GPIO]]] Setting mode of pin {s} to {}\n", .{ self.name, mode });
    }

    fn onRead(_: *GPIOPin) bool {
        return false;
    }

    fn onWrite(pin: *GPIOPin, value: bool) void {
        const self: *Self = @alignCast(@fieldParentPtr("interface", pin));
        if (self.lastValue) |last| {
            if (last == value) {
                return;
            }
        }
        std.debug.print("[[[GPIO]]] Writing value {} to pin {s}\n", .{ value, self.name });
    }
};
