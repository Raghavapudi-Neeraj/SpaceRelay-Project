`timescale 1ns/1ps

module testing;

    reg clk = 0, rst_n;
    reg start_frame;
    reg [1:0] frame_type;
    reg [15:0] txfn, payload_len;
    reg payload_valid;
    reg [7:0] payload_data;

    wire busy, frame_done, frame_valid;
    wire [7:0] frame_data;

    
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

    // Clock
    always #5 clk = ~clk;

    // ---------------- GAP DETECTION ----------------
    integer gap_cnt = 0;
    integer GAP_THRESHOLD = 2; // Threshold is kept to say if there is gap or not in between frames.
    reg prev_valid = 0;
    reg gap_error = 0;

    always @(posedge clk) 
    begin
        prev_valid <= frame_valid;

        if (!frame_valid && prev_valid)
            gap_cnt <= 1;
        else if (!frame_valid && gap_cnt != 0)
            gap_cnt <= gap_cnt + 1;
        else if (frame_valid)
            gap_cnt <= 0;

        if (gap_cnt > GAP_THRESHOLD)
            gap_error <= 1;
    end

    // ---------------- FRAME BYTE COUNT ----------------
    integer frame_byte_cnt = 0;
    always @(posedge clk) 
    begin
        if (frame_valid)
            frame_byte_cnt <= frame_byte_cnt + 1;
    end

    // ---------------- PAYLOAD DRIVER ----------------
    task send_payload(input integer nbytes);
        integer i;
        begin
            // Wait until DUT enters payload state
            wait(dut.present_state == dut.ST_PAYLOAD);
            payload_valid = 1;
            for (i = 0; i < nbytes; i = i + 1) 
            begin
                payload_data = i[7:0];
                @(posedge clk);
            end
            payload_valid = 0;
        end
    endtask

    // ---------------- TEST SEQUENCE ----------------
    initial begin
        $display("3 FRAME CONTINUOUS TEST");
        $dumpfile("three_frames.vcd");
        $dumpvars(0, testing);

        rst_n = 0;
        start_frame = 0;
        payload_valid = 0;
        payload_data = 8'h00;
        frame_type = 2'd1;
        txfn = 16'h1000;

        repeat(10) @(posedge clk);
        rst_n = 1;

        // ---------------- FRAME 1 : payload < 8416 ----------------
        $display("FRAME 1 : payload = 100 bytes");
        payload_len = 16'd100;
        start_frame = 1; 
        @(posedge clk); 
        start_frame = 0;
        send_payload(100);
        @(posedge frame_done);

        // ---------------- FRAME 2 : payload = 8416 ----------------
        $display("FRAME 2 : payload = 8416 bytes");
        txfn = 16'h1001;
        payload_len = 16'd1052; // 8416 bits = 1052 bytes
        start_frame = 1; 
        @(posedge clk); 
        start_frame = 0;
        send_payload(1052);
        @(posedge frame_done);

        // ---------------- FRAME 3 : payload = 0 ----------------
        $display("FRAME 3 : payload = 0 bytes");
        txfn = 16'h1002;
        payload_len = 16'd0;
        start_frame = 1; 
        @(posedge clk); 
        start_frame = 0;
        // no payload sent
        @(posedge frame_done);

        // ---------------- RESULT ----------------
        if (gap_error)
            $display("❌ ERROR: Excessive gap detected between frames!");
        else
            $display("✅ PASS: Continuous frames (within 1-cycle bubble)");

        $display("Total frame bytes sent = %0d", frame_byte_cnt);
        $finish;
    end

endmodule
