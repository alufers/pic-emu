pub const GPIOMode = enum {
    Input,
    Output,
};

pub const GPIOPinVtable = struct {
    setMode: *const fn (self: *GPIOPinVtable, direction: GPIOMode) void,
    read: *const fn (self: *GPIOPinVtable) bool,
    write: *const fn (self: *GPIOPinVtable, value: bool) void,
};

fn nopSetMode(_: *GPIOPinVtable, _: GPIOMode) void {}

fn nopRead(_: *GPIOPinVtable) bool {
    return false;
}

fn nopWrite(_: *GPIOPinVtable, _: bool) void {}

pub const NOPGPIOPin: GPIOPinVtable = .{
    .setMode = nopSetMode,
    .read = nopRead,
    .write = nopWrite,
};
