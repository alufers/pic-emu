const std = @import("std");
const gpio = @import("gpio.zig");

const PIC18 = @import("pic18.zig").PIC18;

test {
    _ = @import("instr_test.zig");
    _ = @import("e2e_test.zig");
}

fn processData(_: void, offset: u32, data: []const u8) !void {
    std.debug.print("read slice @ 0x{x}: {x}\n", .{ offset, data });
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var file = try std.fs.cwd().openFile("./pilot.X.production.hex", .{ .mode = .read_only });
    defer file.close();

    var file_buffer: [1024]u8 = undefined;
    var rdr = file.reader(&file_buffer);

    var pic = PIC18.init(allocator);
    try pic.loadRom(&rdr.interface);

    var spi_cs_pin = gpio.LoggingGPIOPin.init("A.5 [FLASH_CS]");

    pic.GPIOPortA.pins[5] = &spi_cs_pin.interface;

    var cnt: u32 = 0;
    for (0..50_000) |_| {
        if (pic.PC == 0x01b1ce) {
            cnt += 1;
            if (cnt == 1) {
                // Print
            }
            std.debug.print("======PC hit 0x01b1ce! count={}\n", .{cnt});
        }
        pic.execInstruction() catch |err| {
            // Dump memory to file
            var out_file = try std.fs.cwd().createFile("dump.bin", .{ .truncate = true });
            defer out_file.close();
            try out_file.writeAll(pic.MEM);
            return err;
        };
    }
}
