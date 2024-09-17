pub const APnDP = enum(u8) {
    AP = 0b00000010,
    DP = 0b00000000,
};

pub const RnW = enum(u8) {
    R = 0b00000100,
    W = 0b00000000,
};

pub const A32 = enum(u8) {
    A00 = 0b00000000,
    A01 = 0b00001000,
    A10 = 0b00010000,
    A11 = 0b00011000,
};

pub const Perms = enum(u2) {
    RO,
    WO,
    RW,
};

pub const RegisterAddress = struct {
    APnDP: APnDP,
    A: A32,
    /// If null, this value is a don't care
    BANKSEL: ?u4,
    perms: Perms,
};

pub const DPIDR = struct {
    RAO: u1,
    DESIGNER: u11,
    VERSION: u4,
    MIN: u1,
    RESERVED0: u3 = 0,
    PARTNO: u8,
    REVISION: u4,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A00,
        .BANKSEL = null,
        .perms = .RO,
    };
};

pub const ABORT = struct {
    DAPABORT: u1,
    STKCMPCLR: u1,
    STKERRCLR: u1,
    WDERRCLR: u1,
    ORUNERRCLR: u1,
    RESERVED0: u28 = 0,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A00,
        .BANKSEL = null,
        .perms = .WO,
    };
};

pub const CTRL_STAT = packed struct {
    ORUNDETECT: u1,
    STICKYORUN: u1,
    TRNMODE: u2,
    STICKYCMP: u1,
    STICKYERR: u1,
    READOK: u1,
    WDATAERR: u1,
    MASKLANE: u4,
    TRNCNT: u12,
    RESERVED0: u2 = 0,
    CDBGRSTREQ: u1,
    CDBGRSTACK: u1,
    CDBGPWRUPREQ: u1,
    CDBGPWRUPACK: u1,
    CSYSPWRUPREQ: u1,
    CSYSPWRUPACK: u1,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A01,
        .BANKSEL = 0,
        .perms = .RW,
    };
};

pub const DLCR = struct {
    RESERVED3: u6 = 0,
    RESERVED2: u1 = 0b1,
    RESERVED1: u1 = 0,
    TURNAROUND: u2,
    RESERVED0: u21 = 0,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A01,
        .BANKSEL = 1,
        .perms = .RW,
    };
};

pub const TARGETID = struct {
    RAO: u1,
    TDESIGNER: u11,
    TPARTNO: u16,
    TREVISION: u4,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A01,
        .BANKSEL = 2,
        .perms = .RO,
    };
};

pub const DLPIDR = struct {
    PROTVSN: u4,
    RESERVED0: u24 = 0,
    TINSTANCE: u4,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A01,
        .BANKSEL = 3,
        .perms = .RO,
    };
};

pub const EVENTSTAT = struct {
    EA: u1,
    RESERVED0: u31,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A01,
        .BANKSEL = 4,
        .perms = .RO,
    };
};

pub const SELECT = struct {
    DPBANKSEL: u4,
    APBANKSEL: u4,
    RESERVED0: u16 = 0,
    APSEL: u8,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A10,
        .BANKSEL = null,
        .perms = .WO,
    };
};

pub const RESEND = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A10,
        .BANKSEL = null,
        .perms = .RO,
    };
};

pub const RDBUFF = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A11,
        .BANKSEL = null,
        .perms = .RO,
    };
};

pub const TARGETSEL = struct {
    SBO: u1 = 0b1,
    TDESIGNER: u11,
    TPARTNO: u16,
    TINSTANCE: u4,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A11,
        .BANKSEL = null,
        .perms = .WO,
    };
};

pub const AP_IDR = struct {
    TYPE: u4,
    VARIANT: u4,
    RESERVED0: u5 = 0,
    CLASS: u4,
    DESIGNER: u11,
    REVISION: u4,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A11,
        .BANKSEL = 0b1111,
        .perms = .RO,
    };
};

pub const AP_MEM_CSW = struct {
    Size: u3,
    RESERVED1: u1 = 0,
    ADDRINC: u2,
    DEVICEEN: u1,
    TRINPROG: u1,
    MODE: u4,
    TYPE: u3,
    /// If memory tagging control is not implemented, this is bit 5 of TYPE
    MTE: u1,
    RESERVED0: u7 = 0,
    SPIDEN: u1,
    PROT: u7,
    DBGSWENABLE: u1,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b0000,
        .perms = .RW,
    };
};

pub const AP_MEM_TAR_LO = struct {
    ADDR: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A01,
        .BANKSEL = 0b0000,
        .perms = .RW,
    };
};

pub const AP_MEM_TAR_HI = struct {
    ADDR: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A10,
        .BANKSEL = 0b0000,
        .perms = .RW,
    };
};

pub const AP_MEM_DRW = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A11,
        .BANKSEL = 0b0000,
        .perms = .RW,
    };
};

pub const AP_MEM_BD0 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b0001,
        .perms = .RW,
    };
};

pub const AP_MEM_BD1 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A01,
        .BANKSEL = 0b0001,
        .perms = .RW,
    };
};

pub const AP_MEM_BD2 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A10,
        .BANKSEL = 0b0001,
        .perms = .RW,
    };
};

pub const AP_MEM_BD3 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A11,
        .BANKSEL = 0b0001,
        .perms = .RW,
    };
};

pub const AP_MEM_MBT = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b0010,
        .perms = .RW,
    };
};

pub const AP_MEM_T0TR = struct {
    T0: u4,
    T1: u4,
    T2: u4,
    T3: u4,
    T4: u4,
    T5: u4,
    T6: u4,
    T7: u4,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b0011,
        .perms = .RW,
    };
};

pub const AP_MEM_CFG1 = struct {
    TAG0SIZE: u4,
    TAG0GRAN: u5,
    RESERVED0: u23,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b1110,
        .perms = .RO,
    };
};

pub const AP_MEM_BASE_HI = struct {
    BASEADDR_HI: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b1111,
        .perms = .RO,
    };
};

pub const AP_MEM_CFG = struct {
    BE: u1,
    LA: u1,
    LD: u1,
    RESERVED0: u29,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A01,
        .BANKSEL = 0b1111,
        .perms = .RO,
    };
};

pub const AP_MEM_BASE_LO = struct {
    P: u1,
    FORMAT: u1,
    RESERVED0: u10,
    BASEADDR_LO: u20,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A10,
        .BANKSEL = 0b1111,
        .perms = .RO,
    };
};

pub const CORESIGHT_CLASS = enum(u4) {
    GENERIC = 0x0,
    ROMTABLE = 0x1,
    CORESIGHT_COMPONENT = 0x9,
    PERIPHERAL_TEST_BLOCK = 0xB,
    GENERIC_IP_COMPONENT = 0xE,
    OTHER = 0xF,
};

pub const CORESIGHT_CIDR0 = struct {
    PRMBL_0: u8 = 0x0D,
    RES0: u24 = 0x000000,

    pub const addr = 0xFF0;
};

pub const CORESIGHT_CIDR1 = struct {
    PRMBL_1: u4 = 0x0,
    CLASS: CORESIGHT_CLASS = .GENERIC,
    RES0: u24 = 0x000000,

    pub const addr = 0xFF4;
};

pub const CORESIGHT_CIDR2 = struct {
    PRMBL_2: u8,
    RES0: u24,

    pub const addr = 0xFF8;
};

pub const CORESIGHT_CIDR3 = struct {
    PRMBL_3: u8,
    RES0: u24,

    pub const addr = 0xFFC;
};

pub const CORESIGHT_PIDR0 = struct {
    PART_0: u8,
    RES0: u24,

    pub const addr = 0xFE0;
};

pub const CORESIGHT_PIDR1 = struct {
    PART_1: u4,
    DES_0: u4,
    RES0: u24,

    pub const addr = 0xFE4;
};

pub const CORESIGHT_PIDR2 = struct {
    DES_1: u3,
    JEDEC: u1,
    REVISION: u4,
    RES0: u24,

    pub const addr = 0xFE8;
};

pub const CORESIGHT_PIDR3 = struct {
    CMOD: u4,
    REVAND: u4,
    RES0: u24,

    pub const addr = 0xFEC;
};

pub const CORESIGHT_PIDR4 = struct {
    DES_2: u4,
    SIZE: u4,
    RES0: u24,

    pub const addr = 0xFD0;
};

pub const CORESIGHT_PIDR5 = struct {
    RES0: u32,

    pub const addr = 0xFD4;
};

pub const CORESIGHT_PIDR6 = struct {
    RES0: u32,

    pub const addr = 0xFD8;
};

pub const CORESIGHT_PIDR7 = struct {
    RES0: u32,

    pub const addr = 0xFDC;
};

pub const CORESIGHT_AUTHSTATUS = struct {
    NSID: u2,
    NSNID: u2,
    SID: u2,
    SNID: u2,
    HID: u2,
    HNID: u2,
    RLID: u2,
    RLNID: u2,
    NSUID: u2,
    NSUNID: u2,
    SUID: u2,
    SUNID: u2,
    RTID: u2,
    RTNID: u2,
    RES0: u3,

    pub const addr = 0xFB8;
};

pub const CORESIGHT_CLAIMSET = struct {
    SET: u32,

    pub const addr = 0xFA0;
};

pub const CORESIGHT_CLAIMCLR = struct {
    CLR: u32,

    pub const addr = 0xFA4;
};

pub const CORESIGHT_DEVAFF0 = struct {
    DEVAFF0: u32,

    pub const addr = 0xFA8;
};

pub const CORESIGHT_DEVAFF1 = struct {
    DEVAFF1: u32,

    pub const addr = 0xFAC;
};

const CORESIGHT_ARCHID = enum(u16) {
    RAS = 0x0A00,
    ITM = 0x1A01,
    DWT = 0x1A02,
    FPB = 0x1A03,
    ARMV80M = 0x2A04,
    ARMV80R = 0x6A05,
    PC_SAMPLE = 0x0A10,
    ETM = 0x4A13,
    CTI = 0x1A14,
    ARMV80A = 0x6A15,
    ARMV81A = 0x7A15,
    PMU = 0x2A16,
    MEM_AP = 0x0A17,
    JTAG_AP = 0x0A27,
    BASIC_TRACE_ROUTER = 0x0A31,
    POWER_REQUESTER = 0x0A34,
    UNKNOWN_AP = 0x0A47,
    HSSTP = 0x0A50,
    STM = 0x0A63,
    CS_ELA = 0x0A75,
    CS_ROM = 0x0AF7,
    _,
};

pub const CORESIGHT_DEVARCH = struct {
    ARCHID: CORESIGHT_ARCHID,
    REVISION: u4,
    PRESENT: u1,
    ARCHITECT: u11,

    pub const addr = 0xFBC;
};

pub const CORESIGHT_DEVID = struct {
    DEVID: u32,

    pub const addr = 0xFC8;
};

pub const CORESIGHT_DEVID1 = struct {
    DEVID1: u32,

    pub const addr = 0xFC4;
};

pub const CORESIGHT_DEVID2 = struct {
    DEVID: u32,

    pub const addr = 0xFC0;
};

pub const CORESIGHT_DEVTYPE = struct {
    MAJOR: u4,
    SUB: u4,
    RES0: u24,

    pub const addr = 0xFCC;
};

pub const CORESIGHT_ITCTRL = struct {
    IME: u1,
    RES0: u31,

    pub const addr = 0xF00;
};

pub const CORESIGHT_LSR = struct {
    SLI: u1,
    SLK: u1,
    nTT: u1,
    RES0: u29,

    pub const addr = 0xFB4;
};

pub const CORESIGHT_LAR = struct {
    KEY: u32,

    pub const addr = 0xFB0;
};

pub const ROMTABLE_ROMENTRY = struct {
    PRESENT: u1,
    FORMAT: u1,
    POWERIDVALID: u1,
    RES0_0: u1,
    POWERID: u5,
    RES0_1: u3,
    OFFSET: u20,
};
