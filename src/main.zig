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

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var file = try std.Io.Dir.cwd().openFile(init.io, "./pilot.X.production.hex", .{ .mode = .read_only });
    defer file.close(init.io);

    var file_buffer: [1024]u8 = undefined;
    var rdr = file.reader(init.io, &file_buffer);

    var pic = PIC18.init(allocator);
    defer pic.deinit();
    try pic.loadRom(&rdr.interface);

    var spi_cs_pin = gpio.LoggingGPIOPin.init("A.5 [FLASH_CS]");

    pic.GPIOPortA.pins[5] = &spi_cs_pin.interface;

    var cnt: u32 = 0;
    for (0..100000_000) |idx| {
        if (idx % 50000 == 0) {
            std.debug.print("mem[0x01a9]={}, mem[0x01a8]={}\n", .{ pic.MEM[0x01a9], pic.MEM[0x01a8] });
        }
        if (pic.PC == 0x01b1ce) {
            cnt += 1;
            if (cnt == 1) {
                // Print
            }
            std.debug.print("======PC hit 0x01b1ce! count={}\n", .{cnt});
        }
        pic.execInstruction() catch |err| {
            // Dump memory to file
            var out_file = try std.Io.Dir.cwd().createFile(init.io, "dump.bin", .{ .truncate = true });
            defer out_file.close(init.io);
            try out_file.writeStreamingAll(init.io, pic.MEM);
            return err;
        };
    }

    std.debug.print("INTCON val {}\n", .{pic.REGS.INTCON});
    std.debug.print("t0 val timer_value {}\n", .{pic.Timer0.timer_value});
}
