// =============================================================================
// Testbench for tt_um_multi_stage_processor 
// =============================================================================
`timescale 1ns/1ps

module tb_tt_um_multi_stage_processor;

    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out, uio_oe;
    reg ena, clk, rst_n;
    wire [7:0] ua;
    wire VDD, VSS;

    assign VDD = 1'b1;
    assign VSS = 1'b0;
    pullup(ua[1]);    // weak pull: analog_out follows analog_in in stub
    pulldown(ua[0]);

    tt_um_multi_stage_processor dut (
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n),
        .ua(ua), .VDD(VDD), .VSS(VSS)
    );

    always #10 clk = ~clk;   // 50 MHz

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb_tt_um_multi_stage_processor);

        clk = 0; ena = 0; rst_n = 0;
        ui_in = 8'd0;
        uio_in = 8'd0;          // config = 0 initially

        #30 rst_n = 1;
        #10 ena = 1;

        // 1. Test mode (ui_in[7]=1) -> deterministic counter on uo_out
        ui_in = 8'b1_000_0_000; // test_mode=1, debug_sel=0, hold=0, mode=0
        #200;
        $display("Test mode: uo_out = %h (should equal cnt[7:0])", uo_out);

        // 2. Normal operation: mode_sel=3 (analog_sample as source), dynamic config = 4'b0011
        ui_in = 8'b0_001_0_011; // test=0, debug_sel=1 (cnt[15:8]), hold=0, mode=3
        uio_in[3:0] = 4'b0011;  // config = 3
        #200;
        $display("Analog source, config=3: uo_out = %h, debug[7:4] = %h",
                 uo_out, uio_out[7:4]);

        // 3. Change mode to 4 (cnt^lfsr), config=7, debug_sel=6 (src_data)
        ui_in = 8'b0_110_0_100; // debug_sel=6, mode=4
        uio_in[3:0] = 4'b0111;  // config=7
        #200;
        $display("cnt^lfsr src, debug=src_data: uo_out = %h, debug[7:4] = %h",
                 uo_out, uio_out[7:4]);

        // 4. Hold FSM – output should freeze
        ui_in[3] = 1;
        #100;
        $display("Hold: uo_out = %h (should be stable)", uo_out);
        ui_in[3] = 0;
        #50;

        // 5. Sweep debug_sel to verify visibility
        for (integer i=0; i<8; i=i+1) begin
            ui_in[6:4] = i[2:0];
            #60;
            $display("debug_sel=%d -> uio_out[7:4] = %h", i, uio_out[7:4]);
        end

        // 6. Change analog stimulus (affects analog_sample over time)
        //    (In real silicon this would be the analog core; here the stub just passes
        //     ua[1] to ua[0], but we can weakly drive ua[1] to toggle and see effect
        //     on sampled shift register and final output.)
        force ua[1] = 1'b1;
        #200;
        force ua[1] = 1'b0;
        #200;
        release ua[1];
        $display("After analog toggle, uo_out = %h", uo_out);

        #100 $finish;
    end

endmodule
