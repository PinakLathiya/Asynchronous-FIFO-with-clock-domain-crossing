// SVA checks, bound onto async_fifo (use Vivado xsim, Questa, or Verilator --assert).
// Not compiled by Icarus.

module async_fifo_sva #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input logic                  wclk, wrst_n, winc, wfull,
    input logic                  rclk, rrst_n, rinc, rempty,
    input logic [ADDR_WIDTH:0]   wptr, rptr
);
    // Gray-coded pointers change by at most one bit per clock (safe to synchronize)
    a_wptr_gray: assert property (@(posedge wclk) disable iff (!wrst_n)
        $countones(wptr ^ $past(wptr)) <= 1);
    a_rptr_gray: assert property (@(posedge rclk) disable iff (!rrst_n)
        $countones(rptr ^ $past(rptr)) <= 1);

    // Pointer must not move when the FIFO blocks the access
    a_no_wr_when_full:  assert property (@(posedge wclk) disable iff (!wrst_n)
        wfull  |=> $stable(wptr));
    a_no_rd_when_empty: assert property (@(posedge rclk) disable iff (!rrst_n)
        rempty |=> $stable(rptr));

    // Reset state
    a_wrst: assert property (@(posedge wclk) !wrst_n |=> (wptr == '0 && !wfull));
    a_rrst: assert property (@(posedge rclk) !rrst_n |=> (rptr == '0 && rempty));

    // Cover: flags actually get hit
    c_full:  cover property (@(posedge wclk) disable iff (!wrst_n) $rose(wfull));
    c_empty: cover property (@(posedge rclk) disable iff (!rrst_n) $rose(rempty));
endmodule

// bind: .* connects ports and internal signals (wptr, rptr) by name
bind async_fifo async_fifo_sva #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) u_sva (.*);
