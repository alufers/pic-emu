const std = @import("std");

pub const Key = enum {
    left,
    right,
    up,
    down,
    enter,
    one,
    two,
    three,
};

pub const UI = struct {
    const VTable = struct {
        setPixel: *const fn (self: *UI, x: u16, y: u16, color: u16) void,
        exitRequested: *const fn (self: *UI) bool,
        requestExit: *const fn (self: *UI) void,
        isKeyPressed: *const fn (self: *UI, key: Key) bool,
        isKeyDown: *const fn (self: *UI, key: Key) bool,
    };
    vtable: *const VTable,

    /// Write a single RGB565 pixel to the display.
    pub fn setPixel(self: *UI, x: u16, y: u16, color: u16) void {
        self.vtable.setPixel(self, x, y, color);
    }

    /// Whether the user has asked to quit (window close / Esc).
    pub fn exitRequested(self: *UI) bool {
        return self.vtable.exitRequested(self);
    }

    /// Ask the UI to tear down (stop the draw thread, close the window).
    pub fn requestExit(self: *UI) void {
        self.vtable.requestExit(self);
    }

    pub fn isKeyPressed(self: *UI, key: Key) bool {
        return self.vtable.isKeyPressed(self, key);
    }

    /// Level: whether the given key is currently held down.
    pub fn isKeyDown(self: *UI, key: Key) bool {
        return self.vtable.isKeyDown(self, key);
    }
};
