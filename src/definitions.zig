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
    ///Reserved, SBZ.
    RESERVED0: u28 = 0,

    /// To clear the CTRL/STAT.STICKYORUN overrun error bit to 0b0 , write 0b1 to this bit.
    ORUNERRCLR: u1,

    /// To clear the CTRL/STAT.WDATAERR write data error bit to 0b0, write 0b1 to this bit.
    WDERRCLR: u1,

    /// To clear the CTRL/STAT.STICKYERR sticky error bit to 0b0, write 0b1 to this bit.
    STKERRCLR: u1,

    /// To clear the CTRL/STAT.STICKYCMP sticky compare bit to 0b0, write 0b1 to this bit. It is
    /// IMPLEMENTATION DEFINED whether the CTRL/STAT.STICKYCMP bit is implemented.
    STKCMPCLR: u1,

    /// To generate a DAP abort, which aborts the current AP transaction, write 0b1 to this bit.
    /// Do this write only if the debugger has received WAIT responses over an extended period.
    /// In DPv0, this bit is SBO.
    DAPABORT: u1,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A00,
        .BANKSEL = null,
        .perms = .WO,
    };
};

pub const CTRL_STAT = packed struct {
    CSYSPWRUPACK: u1,
    CSYSPWRUPREQ: u1,
    CDBGPWRUPACK: u1,
    CDBGPWRUPREQ: u1,
    CDBGRSTACK: u1,
    CDBGRSTREQ: u1,
    RESERVED0: u2 = 0,
    TRNCNT: u12,
    MASKLANE: u4,
    WDATAERR: u1,
    READOK: u1,
    STICKYERR: u1,
    STICKYCMP: u1,
    TRNMODE: enum(u2) {
        normal_operation = 0b00,
        pushed_verify = 0b01,
        pushed_compare = 0b10,
        reserved0 = 0b11,
    },
    STICKYORUN: u1,
    ORUNDETECT: u1,

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
    TINSTANCE: u4,
    TPARTNO: u16,
    TDESIGNER: u11,
    SBO: u1,

    pub const addr = RegisterAddress{
        .APnDP = .DP,
        .A = .A11,
        .BANKSEL = null,
        .perms = .WO,
    };
};

pub const AP_IDR = struct {
    REVISION: u4,
    DESIGNER: u11,
    CLASS: u4,
    RESERVED0: u5 = 0,
    VARIANT: u4,
    TYPE: u4,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A11,
        .BANKSEL = 0b11111,
        .perms = .RO,
    };
};

pub const AP_MEM_CSW = struct {
    DBGSWENABLE: u1,
    PROT: u7,
    SPIDEN: u1,
    RESERVED0: u7 = 0,
    /// If memory tagging control is not implemented, this is bit 5 of TYPE
    MTE: u1,
    TYPE: u3,
    MODE: u4,
    TRINPROG: u1,
    DEVICEEN: u1,
    ADDRINC: u2,
    RESERVED1: u1 = 0,
    Size: u3,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b00000,
        .perms = .RW,
    };
};

pub const AP_MEM_TAR_LO = struct {
    ADDR: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A01,
        .BANKSEL = 0b00000,
        .perms = .RW,
    };
};

pub const AP_MEM_TAR_HI = struct {
    ADDR: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A10,
        .BANKSEL = 0b00000,
        .perms = .RW,
    };
};

pub const AP_MEM_DRW = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A11,
        .BANKSEL = 0b00000,
        .perms = .RW,
    };
};

pub const AP_MEM_BD0 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b00001,
        .perms = .RW,
    };
};

pub const AP_MEM_BD1 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A01,
        .BANKSEL = 0b00001,
        .perms = .RW,
    };
};

pub const AP_MEM_BD2 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A10,
        .BANKSEL = 0b00001,
        .perms = .RW,
    };
};

pub const AP_MEM_BD3 = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A11,
        .BANKSEL = 0b00001,
        .perms = .RW,
    };
};

pub const AP_MEM_MBT = struct {
    DATA: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b00010,
        .perms = .RW,
    };
};

pub const AP_MEM_T0TR = struct {
    T7: u4,
    T6: u4,
    T5: u4,
    T4: u4,
    T3: u4,
    T2: u4,
    T1: u4,
    T0: u4,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b00011,
        .perms = .RW,
    };
};

pub const AP_MEM_CFG1 = struct {
    RESERVED0: u23,
    TAG0GRAN: u5,
    TAG0SIZE: u4,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b01110,
        .perms = .RO,
    };
};

pub const AP_MEM_BASE_HI = struct {
    BASEADDR_HI: u32,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A00,
        .BANKSEL = 0b01111,
        .perms = .RO,
    };
};

pub const AP_MEM_CFG = struct {
    RESERVED0: u29,
    LD: u1,
    LA: u1,
    BE: u1,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A01,
        .BANKSEL = 0b01111,
        .perms = .RO,
    };
};

pub const AP_MEM_CFG_LO = struct {
    BASEADDR_LO: u20,
    RESERVED0: u10,
    FORMAT: u1,
    P: u1,

    pub const addr = RegisterAddress{
        .APnDP = .AP,
        .A = .A10,
        .BANKSEL = 0b01111,
        .perms = .RO,
    };
};
