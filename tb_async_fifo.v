`timescale 1ns/1ps
// Self-checking testbench: scoreboard (data order/integrity), overflow/underflow checks,
// randomized traffic in several phases, full/empty hit counters.
// Override clock ratio with: -P tb_async_fifo.WH=<half-period> -P tb_async_fifo.RH=<half-period>
module tb_async_fifo;
    parameter DW     = 8;
    parameter AW     = 4;
    parameter WH     = 5;      // wclk half period (ns)
    parameter RH     = 7;      // rclk half period (ns)
    parameter CYCLES = 20000;  // wclk cycles per phase
    localparam DEPTH = 1 << AW;

    reg  wclk = 0, rclk = 0, wrst_n = 0, rrst_n = 0, winc = 0, rinc = 0;
    reg  [DW-1:0] wdata = 0;
    wire wfull, rempty;
    wire [DW-1:0] rdata;

    async_fifo #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW)) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty));

    always #WH wclk = ~wclk;
    initial begin #3; forever #RH rclk = ~rclk; end   // offset so edges are not aligned

    // ---------------- random stimulus ----------------
    integer wprob = 50, rprob = 50;   // percent chance of requesting a write / read per cycle

    always @(posedge wclk) if (wrst_n) begin
        winc  <= (($random & 32'h7fffffff) % 100) < wprob;
        wdata <= $random;
    end
    always @(posedge rclk) if (rrst_n)
        rinc  <= (($random & 32'h7fffffff) % 100) < rprob;

    // ---------------- scoreboard / checkers ----------------
    reg [DW-1:0] sb [0:1023];
    integer wr_cnt = 0, rd_cnt = 0, errors = 0;
    integer full_cyc = 0, empty_cyc = 0, full_rise = 0, empty_rise = 0;
    reg wfull_q = 0, rempty_q = 1;

    always @(posedge wclk) if (wrst_n) begin
        if (winc && !wfull) begin
            if (wr_cnt - rd_cnt >= DEPTH) begin
                errors = errors + 1;
                $display("[%0t] ERROR overflow: write accepted while FIFO truly full", $time);
            end
            sb[wr_cnt % 1024] = wdata;
            wr_cnt = wr_cnt + 1;
        end
        if (wfull) full_cyc = full_cyc + 1;
        if (wfull && !wfull_q) full_rise = full_rise + 1;
        wfull_q <= wfull;
    end

    always @(posedge rclk) if (rrst_n) begin
        if (rinc && !rempty) begin
            if (rd_cnt >= wr_cnt) begin
                errors = errors + 1;
                $display("[%0t] ERROR underflow: read accepted while FIFO truly empty", $time);
            end else if (rdata !== sb[rd_cnt % 1024]) begin
                errors = errors + 1;
                $display("[%0t] ERROR data mismatch #%0d: got %h expected %h",
                         $time, rd_cnt, rdata, sb[rd_cnt % 1024]);
            end
            rd_cnt = rd_cnt + 1;
        end
        if (rempty) empty_cyc = empty_cyc + 1;
        if (rempty && !rempty_q) empty_rise = empty_rise + 1;
        rempty_q <= rempty;
    end

    // ---------------- test sequence ----------------
    task run_phase(input [8*12-1:0] name, input integer wp, input integer rp);
        begin
            wprob = wp; rprob = rp;
            $display("  phase %-12s wprob=%0d%% rprob=%0d%%", name, wp, rp);
            repeat (CYCLES) @(posedge wclk);
        end
    endtask

    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_async_fifo);
        end
        $display("async_fifo test: DW=%0d DEPTH=%0d wclk=%0d ns rclk=%0d ns", DW, DEPTH, 2*WH, 2*RH);

        #50;
        @(posedge wclk); #1 wrst_n = 1;
        @(posedge rclk); #1 rrst_n = 1;

        run_phase("balanced",    50,  50);
        run_phase("write-heavy", 90,  20);
        run_phase("read-heavy",  20,  90);
        run_phase("back-to-back", 100, 100);
        run_phase("bursty-fill", 100,   5);
        run_phase("bursty-drain",  5, 100);

        // drain
        wprob = 0; rprob = 100;
        repeat (200) @(posedge rclk);
        repeat (20)  @(posedge wclk);

        if (rd_cnt !== wr_cnt) begin
            errors = errors + 1;
            $display("ERROR: %0d written but %0d read after drain", wr_cnt, rd_cnt);
        end
        if (!rempty) begin errors = errors + 1; $display("ERROR: rempty not asserted after drain"); end
        if (wfull)   begin errors = errors + 1; $display("ERROR: wfull still asserted after drain"); end
        if (full_rise == 0 || empty_rise == 0) begin
            errors = errors + 1; $display("ERROR: full/empty never exercised");
        end

        $display("  writes=%0d reads=%0d full_events=%0d empty_events=%0d errors=%0d",
                 wr_cnt, rd_cnt, full_rise, empty_rise, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end

    initial begin   // watchdog
        #(CYCLES * 2 * WH * 20);
        $display("FAIL: timeout");
        $finish;
    end
endmodule
