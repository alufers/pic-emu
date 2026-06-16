pub const LcdCommand = enum(u8) {
    // Level 1 Commands
    /// Software Reset
    swreset = 0x01,
    /// Read display identification information
    read_display_id = 0x04,
    /// Read Display Status
    rddst = 0x09,
    /// Read Display Power Mode
    rddpm = 0x0A,
    /// Read Display MADCTL
    rddmadctl = 0x0B,
    /// Read Display Pixel Format
    rddcolmod = 0x0C,
    /// Read Display Image Format
    rddim = 0x0D,
    /// Read Display Signal Mode
    rddsm = 0x0E,
    /// Read Display Self-Diagnostic Result
    rddsdr = 0x0F,
    /// Enter Sleep Mode
    splin = 0x10,
    /// Sleep out register
    sleep_out = 0x11,
    /// Partial Mode ON
    ptlon = 0x12,
    /// Normal Display Mode ON
    normal_mode_on = 0x13,
    /// Display Inversion OFF
    dinvoff = 0x20,
    /// Display Inversion ON
    dinvon = 0x21,
    /// Gamma register
    gamma = 0x26,
    /// Display off register
    display_off = 0x28,
    /// Display on register
    display_on = 0x29,
    /// Column address register
    column_addr = 0x2A,
    /// Page address register
    page_addr = 0x2B,
    /// GRAM register
    gram = 0x2C,
    /// Color SET
    rgbset = 0x2D,
    /// Memory Read
    ramrd = 0x2E,
    /// Partial Area
    pltar = 0x30,
    /// Vertical Scrolling Definition
    vscrdef = 0x33,
    /// Tearing Effect Line OFF
    teoff = 0x34,
    /// Tearing Effect Line ON
    teon = 0x35,
    /// Memory Access Control register
    mac = 0x36,
    /// Vertical Scrolling Start Address
    vscrsadd = 0x37,
    /// Idle Mode OFF
    idmoff = 0x38,
    /// Idle Mode ON
    idmon = 0x39,
    /// Pixel Format register
    pixel_format = 0x3A,
    /// Write Memory Continue
    write_mem_continue = 0x3C,
    /// Read Memory Continue
    read_mem_continue = 0x3E,
    /// Set Tear Scanline
    set_tear_scanline = 0x44,
    /// Get Scanline
    get_scanline = 0x45,
    /// Write Brightness Display register
    wdb = 0x51,
    /// Read Display Brightness
    rddisbv = 0x52,
    /// Write Control Display register
    wcd = 0x53,
    /// Read CTRL Display
    rdctrld = 0x54,
    /// Write Content Adaptive Brightness Control
    wrcabc = 0x55,
    /// Read Content Adaptive Brightness Control
    rdcabc = 0x56,
    /// Write CABC Minimum Brightness
    write_cabc = 0x5E,
    /// Read CABC Minimum Brightness
    read_cabc = 0x5F,
    /// Read ID1
    read_id1 = 0xDA,
    /// Read ID2
    read_id2 = 0xDB,
    /// Read ID3
    read_id3 = 0xDC,

    // Level 2 Commands
    /// RGB Interface Signal Control
    rgb_interface = 0xB0,
    /// Frame Rate Control (In Normal Mode)
    frmctr1 = 0xB1,
    /// Frame Rate Control (In Idle Mode)
    frmctr2 = 0xB2,
    /// Frame Rate Control (In Partial Mode)
    frmctr3 = 0xB3,
    /// Display Inversion Control
    invtr = 0xB4,
    /// Blanking Porch Control register
    bpc = 0xB5,
    /// Display Function Control register
    dfc = 0xB6,
    /// Entry Mode Set
    etmod = 0xB7,
    /// Backlight Control 1
    backlight1 = 0xB8,
    /// Backlight Control 2
    backlight2 = 0xB9,
    /// Backlight Control 3
    backlight3 = 0xBA,
    /// Backlight Control 4
    backlight4 = 0xBB,
    /// Backlight Control 5
    backlight5 = 0xBC,
    /// Backlight Control 7
    backlight7 = 0xBE,
    /// Backlight Control 8
    backlight8 = 0xBF,
    /// Power Control 1 register
    power1 = 0xC0,
    /// Power Control 2 register
    power2 = 0xC1,
    /// VCOM Control 1 register
    vcom1 = 0xC5,
    /// VCOM Control 2 register
    vcom2 = 0xC7,
    /// NV Memory Write
    nvmwr = 0xD0,
    /// NV Memory Protection Key
    nvmpkey = 0xD1,
    /// NV Memory Status Read
    rdnvm = 0xD2,
    /// Read ID4
    read_id4 = 0xD3,
    /// Positive Gamma Correction register
    pgamma = 0xE0,
    /// Negative Gamma Correction register
    ngamma = 0xE1,
    /// Digital Gamma Control 1
    dgamctrl1 = 0xE2,
    /// Digital Gamma Control 2
    dgamctrl2 = 0xE3,
    /// Interface control register
    interface = 0xF6,

    // Extend register commands
    /// Power control A register
    powera = 0xCB,
    /// Power control B register
    powerb = 0xCF,
    /// Driver timing control A
    dtca = 0xE8,
    /// Driver timing control B
    dtcb = 0xEA,
    /// Power on sequence register
    power_seq = 0xED,
    /// 3 Gamma enable register
    @"3gamma_en" = 0xF2,
    /// Pump ratio control register
    prc = 0xF7,

    _,
};
