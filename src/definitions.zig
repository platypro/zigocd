const SwdWriteOp = struct {
    Start: u1 = 1,
    APnDP: enum(u1) {
        AP = 1,
        DP = 0,
    },
    RnW: enum(u1) {
        R = 1,
        W = 0,
    },
    A: u2,
    Parity: u1,
    Stop: u1 = 0,
    Park: u1 = 1,
    Trn1: u1 = 0,
    Ack: u3 = 0,
    Trn2: u1 = 0,

    const Dir = SwdWriteOp{
        .Start = 1, // Out
        .APnDP = 1, // Out
        .RnW = 1, // Out
        .A = 0x3, // Out
        .Parity = 1, // Out
        .Stop = 1, // Out
        .Park = 1, // Out
        .Trn1 = 0, // Turnaround (In)
        .Ack = 0, // In
        .Trn2 = 0, // Turnaround (In)
    };
};

const SwdReadData = struct {
    data: u32,
    parity: u1,

    const Dir = SwdReadData{
        .data = 0x00000000, // In
        .parity = 0x0, // In
    };
};

const SwdWriteData = struct {
    data: u32,
    parity: u1,

    const Dir = SwdWriteData{
        .data = 0xFFFFFFFF, // Out
        .parity = 0x1, // Out
    };
};
