const std = @import("std");
const gpio = @import("gpio.zig");

const PIC18 = @import("pic18.zig").PIC18;
const spi_flash = @import("spi_flash.zig");
const spi_si4455_radio = @import("spi_si4455_radio.zig");
const IL9341_display = @import("ili9341_display.zig");
const RaylibUI = @import("raylib_ui.zig").RaylibUI;
const gpio_button = @import("gpio_button.zig");
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

    var addrs_file = try std.Io.Dir.cwd().openFile(init.io, "./addrs.json", .{ .mode = .read_only });
    defer addrs_file.close(init.io);

    var addrs_file_buffer: [1024]u8 = undefined;
    var addrs_rdr = addrs_file.reader(init.io, &addrs_file_buffer);

    try pic.loadFunctionsList(&addrs_rdr.interface);

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

    var radio = spi_si4455_radio.SPISi4455Radio.init(pic);

    pic.MSSP1.slave = &radio.spiSlaveInterface;
    pic.GPIOPortD.pins[3] = &radio.csPinInterface;

    var ui_impl = try RaylibUI.init(allocator);
    defer ui_impl.deinit();

    var disp = try IL9341_display.ILI9341Display.init(allocator, pic, &ui_impl.interface);
    defer disp.deinit();
    // var disp_wr = gpio.LoggingGPIOPin.init("G.1 [DISP_WR]");

    pic.GPIOPortG.pins[1] = &disp.wrPinInterface;
    pic.GPIOPortG.pins[2] = &disp.dcPinInterface;

    for (0..8) |idx| {
        pic.GPIOPortE.pins[idx] = &disp.dataPins[idx].interface;
    }

    // pic.PC = 0xd02;
    // pic.REGS.WREG.* = 0x0F;

    // Buttons
    var down_button = gpio_button.GPIOButton.init(pic, &ui_impl.interface, .down);

    pic.GPIOPortF.pins[1] = &down_button.pinInterface;

    // for (0..5000) |_| {
    //     pic.execInstruction() catch {
    //         std.debug.print("ICON {x:02}{x:02}{x:02}{x:02}\n", .{ pic.MEM[0xf], pic.MEM[0xe], pic.MEM[0xd], pic.MEM[0xc] });
    //         return;
    //     };
    // }

    for (0x2000..(0x2000 + 32)) |i| {
        data_flash.flashBuf[i] = 0xFF;
    }

    for (0..900000_000) |idx| {
        if (ui_impl.interface.exitRequested()) {
            break;
        }

        down_button.fireInterruptIfNeeded();

        // if (pic.PC == 0x002788) {
        //     std.debug.print("DELAY\n", .{});
        //     pic.PC = 0x0027bc; // Skip over delays, ugly hack because the timer takes FOR EVA
        // }

        // if (pic.PC == 0x1f120) {
        //     // hangs waiting for button press
        //     std.debug.print("SKIP generate_remote_serial\n", .{});
        //     pic.PC = 0x1f198;
        // }

        // if (pic.PC == 0x00395c) {
        //     // hangs waiting for radio status
        //     std.debug.print("SKIP Si4455_ReinitAndRx\n", .{});
        //     pic.PC = 0x0084a;
        // }

        // if (pic.PC == 0x00102c) {
        //     std.debug.print("SKIP Radio_ReceiveData\n", .{});
        //     pic.PC = 0x001084;
        // }
        // if (pic.PC == 0x01a296) {
        //     // Skip SerialCommand_Handler
        //     // std.debug.print("skip SerialCommand_Handler", .{});
        //     pic.PC = 0x01a2d8;
        // }

        if (pic.PC == 0x000d02) {
            // print drawn icons
            std.debug.print("ICON ID = {}\n", .{pic.REGS.WREG.*});
        }

        if (pic.PC == 0x013ac4) {
            const text_addr = std.mem.readInt(u16, pic.MEM[0x3c .. 0x3c + 2], .little);

            std.debug.print("LCD_draw_text: {s}\n", .{std.mem.sliceTo(pic.MEM[text_addr..][0..109], 0)});

            pic.printStackTrace();

            // std.debug.print("FLASH_TABLE_OFFSET = {x}", .{std.mem.readInt(u32, pic.MEM[0x3d1..][0..4], .little)});
        }

        if (pic.PC == 0x016830) {
            std.debug.print("!!!!!!!!!!!!!!!!! REACHED FUN_CODE_016830\n", .{});
        }

        // if (pic.PC == 0x01d90a) {
        //     std.debug.print("LCD_DrawSprite\n", .{});
        //     pic.printStackTrace();
        // }

       

        if (pic.PC == 0x1e12) {
            pic.enableTrace = true;
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
