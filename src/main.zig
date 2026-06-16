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

    // var spi_cs_pin = gpio.LoggingGPIOPin.init("A.5 [FLASH_CS]");

    var flash_file = try std.Io.Dir.cwd().openFile(init.io, "./flash.bin", .{ .mode = .read_only });

    defer flash_file.close(init.io);
    const flash_stat = try flash_file.stat(init.io);
    const flash_data = try init.gpa.alloc(u8, flash_stat.size);
    defer init.gpa.free(flash_data);

    _ = try std.Io.Dir.readFile(std.Io.Dir.cwd(), init.io, "flash.bin", flash_data);

    var data_flash = spi_flash.SPIFlash.init(pic, flash_data);
    pic.MSSP2.slave = &data_flash.spiSlaveInterface;
    pic.GPIOPortA.pins[5] = &data_flash.csPinInterface;

    var disp = try IL9341_display.ILI9341Display.init(allocator, pic);
    defer disp.deinit();
    // var disp_wr = gpio.LoggingGPIOPin.init("G.1 [DISP_WR]");

    pic.GPIOPortG.pins[1] = &disp.wrPinInterface;
    pic.GPIOPortG.pins[2] = &disp.dcPinInterface;

    for (0..8) |idx| {
        pic.GPIOPortE.pins[idx] = &disp.dataPins[idx].interface;
    }

    for (0..100000_000) |_| {
        if (pic.PC == 0x002788) {
            std.debug.print("DELAY\n", .{});
            pic.PC = 0x0027bc; // Skip over delays, ugly hack because the timer takes FOR EVA
        }

        if (pic.PC == 0x1f120) {
            std.debug.print("SKIP _modify_rolling_code_and_radio_proto\n", .{});
            pic.PC = 0x1f198;
        }

        if (pic.PC == 0x001ddc) {
            std.debug.print("SKIP EEPROM_WriteByte\n", .{});
            pic.PC = 0x001e22;
        }

        if (pic.PC == 0x00395c) {
            std.debug.print("SKIP Si4455_ReinitAndRx\n", .{});
            pic.PC = 0x0084a;
        }

        if (pic.PC == 0x0038cc) {
            std.debug.print("SKIP ADC_READ\n", .{});
            pic.PC = 0x0038e2;
        }

        if (pic.PC == 0x013fcc) {
            std.debug.print("SKIP Si4455_ProcessReceived\n", .{});
            pic.PC = 0x0143cc;
        }

        pic.execInstruction() catch |err| {
            // Dump memory to file
            var out_file = try std.Io.Dir.cwd().createFile(init.io, "dump.bin", .{ .truncate = true });
            defer out_file.close(init.io);
            try out_file.writeStreamingAll(init.io, pic.MEM);
            return err;
        };
    }

    pic.printStackTrace();
}
