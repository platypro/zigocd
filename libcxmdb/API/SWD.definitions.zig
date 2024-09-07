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

pub const AP_MEM_CFG_LO = struct {
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
