`timescale 1ns / 1ps
module testing();

    reg clk = 0, rst_n, start_frame;
    reg [1:0] frame_type;
    reg [15:0] txfn, payload_len;
    reg payload_valid;
    reg [7:0] payload_data;
    
    wire busy, frame_done, frame_valid;
    wire [7:0] frame_data;
    
    // DUT
    framer #(
        .PL_RATE(2),
        .DATA_WIDTH(8)
    ) dut (
    .clk(clk),      
    .rst_n(rst_n), 
    .start_frame(start_frame),
    .frame_type(frame_type), 
    .txfn(txfn),
    .payload_valid(payload_valid), 
    .payload_data(payload_data), 
    .payload_len(payload_len),
    .busy(busy), 
    .frame_done(frame_done), 
    .frame_valid(frame_valid), 
    .frame_data(frame_data)
);

    
    always #5 clk = ~clk;  // 100MHz
    
    integer frame_bytes = 0;
    reg [7:0] captured [0:5000];
    
    always @(posedge clk) begin
        if (frame_valid) begin
            captured[frame_bytes] <= frame_data;
            frame_bytes <= frame_bytes + 1;
        end
    end
    
    initial begin
        $display("=== OCT-060 BACK-TO-BACK TEST ===");
        $dumpfile("back2back.vcd");
        
        // Reset
        rst_n = 0; start_frame = 0; payload_valid = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        
        // FRAME 1
        $display("\nT=%0t: FRAME 1 START", $time);
        frame_type = 2'd1; txfn = 16'h1234; payload_len = 16'd20;
        payload_data = 8'hAA; payload_valid = 1;
        start_frame = 1; @(posedge clk); start_frame = 0;
        
        repeat(20) @(posedge clk); payload_valid = 0;
        wait(busy == 0);
        $display("T=%0t: FRAME 1 DONE (busy=0)", $time);
        
        // MEASURE CRITICAL GAP
        repeat(1) @(posedge clk);  // Wait 1 cycle max
        if (busy || frame_valid) 
            $display("? NO GAP!");
        else 
            $display("? GAP DETECTED!");
        
        // FRAME 2 - IMMEDIATE
        $display("T=%0t: FRAME 2 START", $time);
        txfn = 16'h1235;  // Next sequence
        start_frame = 1; @(posedge clk); start_frame = 0;
        payload_valid = 1; repeat(20) @(posedge clk); payload_valid = 0;
        wait(busy == 0);
        $display("T=%0t: FRAME 2 DONE ?", $time);
        
        $display("\n=== Frame 1 ends @ byte %d, Frame 2 starts @ %d ===", 
                 frame_bytes-1400, frame_bytes-1200);
                 
        if (frame_bytes > 2500) $display("? BACK-TO-BACK SUCCESS!");
        $finish;
    end

endmodule
