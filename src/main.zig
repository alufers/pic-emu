const std = @import("std");
const gpio = @import("gpio.zig");

const PIC18 = @import("pic18.zig").PIC18;
const spi_flash = @import("spi_flash.zig");
const IL9341_display = @import("ili9341_display.zig");

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

    var disp = try IL9341_display.ILI9341Display.init(allocator, pic);
    defer disp.deinit();
    // var disp_wr = gpio.LoggingGPIOPin.init("G.1 [DISP_WR]");

    pic.GPIOPortG.pins[1] = &disp.wrPinInterface;
    pic.GPIOPortG.pins[2] = &disp.dcPinInterface;

    for (0..8) |idx| {
        pic.GPIOPortE.pins[idx] = &disp.dataPins[idx].interface;
    }

    var data_flash = spi_flash.SPIFlash.init();
    pic.MSSP2.slave = &data_flash.spiSlaveInterface;

    for (0..300000_0000) |_| {
        if (pic.PC == 0x002788) {
            std.debug.print("DELAY", .{});
            pic.PC = 0x0027bc; // Skip over delays, ugly hack because the timer takes FOR EVA
        }
        if (pic.PC == 0x015026) {
            std.debug.print("LOLOLOLO", .{});
            // return;
        }
        pic.execInstruction() catch |err| {
            // Dump memory to file
            var out_file = try std.Io.Dir.cwd().createFile(init.io, "dump.bin", .{ .truncate = true });
            defer out_file.close(init.io);
            try out_file.writeStreamingAll(init.io, pic.MEM);
            return err;
        };
    }
}
