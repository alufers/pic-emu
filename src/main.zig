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

    for (0..1000000_000) |_| {
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

        if (pic.PC >= 0x01d90a and pic.PC <= 0x01d9c6) { // Slow down draw sprite
            // var threaded: std.Io.Threaded = .init_single_threaded;
            // const io = threaded.io();

            // std.debug.print("FLASH_TABLE = 0x{x}\n", .{std.mem.readInt(u32, pic.MEM[0x03d1..(0x03d1 + 4)], .little)});

            // std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(2), .real) catch unreachable;
            // pic.printStackTrace();

            // const tblptr: u21 = (@as(u21, pic.REGS.TBLPTRU.* & 0x0F) << 16) | (@as(u21, pic.REGS.TBLPTRH.*) << 8) | @as(u21, pic.REGS.TBLPTRL.*);
            // std.debug.print("TBLPTR = 0x{x}\n", .{tblptr});
        }

        if (pic.PC == 0x01fc2c) {
            std.debug.print("WREG AT Flash_ReadString = 0x{x}\n", .{pic.REGS.WREG.*});

            if (pic.REGS.WREG.* == 0x32) { // Catch "Zapisz"
                // pic.printStackTrace();
            }
        }

        // On return of Flash_ReadString
        if (pic.PC == 0x01fcac) {
            // Print read out string
            const stringVarPtr = pic.MEM[0x0768 .. 0x0768 + 30];
            std.debug.print("STR_BUF = {x}\n", .{stringVarPtr});
        }

        // Trace LCD_draw_text
        if (pic.PC == 0x013ac4) {
            // pic.MEM[0x0768] = 'A';

            std.Io.sleep(init.io, std.Io.Duration.fromMilliseconds(500), .real) catch unreachable;
            pic.MEM[0x35] = 0;
            pic.MEM[0x36] = 0;
            std.debug.print("LCD_draw_text X = 0x{x}\n", .{std.mem.readInt(u16, pic.MEM[0x33..(0x33 + 2)], .little)});
            std.debug.print("LCD_draw_text Y = 0x{x}\n", .{std.mem.readInt(u16, pic.MEM[0x35..(0x35 + 2)], .little)});
            std.debug.print("LCD_draw_text TEXT_ADDR = 0x{x}\n", .{std.mem.readInt(u16, pic.MEM[0x3c..(0x3c + 2)], .little)});

            pic.printStackTrace();
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
