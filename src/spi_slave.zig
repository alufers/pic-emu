const std = @import("std");

// SPI interface description

pub const SPISlave = struct {
    const VTable = struct {
        transact: *const fn (self: *SPISlave, mosi: u8) u8,
    };
    vtable: *const VTable,

    pub fn transact(self: *SPISlave, mosi: u8) u8 {
        return self.vtable.transact(self, mosi);
    }
};

fn nopTransact(_: *SPISlave, _: u8) u8 {
    return 0;
}

pub const NOPSPISlave: SPISlave = .{
    .vtable = &.{
        .transact = nopTransact,
    },
};
