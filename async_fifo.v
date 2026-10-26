// Asynchronous FIFO (Cummings-style)
//  - Gray-coded pointers, 2-FF synchronizers across the clock domains
//  - Depth = 2**ADDR_WIDTH (ADDR_WIDTH >= 2)
//  - rdata is combinational from the memory: valid whenever rempty == 0 (first-word fall-through)
//  - wfull / rempty are conservative: they may stay asserted a few cycles late, never early

module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    // write domain
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [DATA_WIDTH-1:0] wdata,
    output wire                  wfull,
    // read domain
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    output wire [DATA_WIDTH-1:0] rdata,
    output wire                  rempty
);
    wire [ADDR_WIDTH-1:0] waddr, raddr;
    wire [ADDR_WIDTH:0]   wptr, rptr;          // gray
    wire [ADDR_WIDTH:0]   wq2_rptr, rq2_wptr;  // synchronized gray

    sync_2ff #(.WIDTH(ADDR_WIDTH+1)) u_sync_r2w (
        .clk(wclk), .rst_n(wrst_n), .d(rptr), .q(wq2_rptr));

    sync_2ff #(.WIDTH(ADDR_WIDTH+1)) u_sync_w2r (
        .clk(rclk), .rst_n(rrst_n), .d(wptr), .q(rq2_wptr));

    fifo_mem #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_mem (
        .wclk(wclk), .wen(winc & ~wfull), .waddr(waddr), .wdata(wdata),
        .raddr(raddr), .rdata(rdata));

    wptr_full #(.ADDR_WIDTH(ADDR_WIDTH)) u_wptr_full (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wq2_rptr(wq2_rptr),
        .wfull(wfull), .waddr(waddr), .wptr(wptr));

    rptr_empty #(.ADDR_WIDTH(ADDR_WIDTH)) u_rptr_empty (
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rq2_wptr(rq2_wptr),
        .rempty(rempty), .raddr(raddr), .rptr(rptr));
endmodule


// Two-flop synchronizer (async reset)
module sync_2ff #(parameter WIDTH = 5) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q
);
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] ff1, ff2;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) {ff2, ff1} <= {2*WIDTH{1'b0}};
        else        {ff2, ff1} <= {ff1, d};
    assign q = ff2;
endmodule


// Dual-port memory: write on wclk, combinational read
module fifo_mem #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wclk,
    input  wire                  wen,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output wire [DATA_WIDTH-1:0] rdata
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    assign rdata = mem[raddr];
    always @(posedge wclk)
        if (wen) mem[waddr] <= wdata;
endmodule


// Write pointer + full flag (write domain)
module wptr_full #(parameter ADDR_WIDTH = 4) (
    input  wire                  wclk,
    input  wire                  wrst_n,
    input  wire                  winc,
    input  wire [ADDR_WIDTH:0]   wq2_rptr,
    output reg                   wfull,
    output wire [ADDR_WIDTH-1:0] waddr,
    output reg  [ADDR_WIDTH:0]   wptr
);
    reg  [ADDR_WIDTH:0] wbin;
    wire [ADDR_WIDTH:0] wbin_next  = wbin + (winc & ~wfull);
    wire [ADDR_WIDTH:0] wgray_next = (wbin_next >> 1) ^ wbin_next;

    // full: next gray write ptr equals synced read ptr with the top two bits inverted
    wire wfull_val = (wgray_next ==
                     {~wq2_rptr[ADDR_WIDTH:ADDR_WIDTH-1], wq2_rptr[ADDR_WIDTH-2:0]});

    assign waddr = wbin[ADDR_WIDTH-1:0];

    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n) {wbin, wptr} <= 0;
        else         {wbin, wptr} <= {wbin_next, wgray_next};

    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= wfull_val;
endmodule


// Read pointer + empty flag (read domain)
module rptr_empty #(parameter ADDR_WIDTH = 4) (
    input  wire                  rclk,
    input  wire                  rrst_n,
    input  wire                  rinc,
    input  wire [ADDR_WIDTH:0]   rq2_wptr,
    output reg                   rempty,
    output wire [ADDR_WIDTH-1:0] raddr,
    output reg  [ADDR_WIDTH:0]   rptr
);
    reg  [ADDR_WIDTH:0] rbin;
    wire [ADDR_WIDTH:0] rbin_next  = rbin + (rinc & ~rempty);
    wire [ADDR_WIDTH:0] rgray_next = (rbin_next >> 1) ^ rbin_next;

    // empty: next gray read ptr equals synced write ptr
    wire rempty_val = (rgray_next == rq2_wptr);

    assign raddr = rbin[ADDR_WIDTH-1:0];

    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n) {rbin, rptr} <= 0;
        else         {rbin, rptr} <= {rbin_next, rgray_next};

    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= rempty_val;
endmodule
