`timescale 1ns / 1ps

module framer 
    #(parameter PREAMBLE_BITS = 64,
    parameter HEADER_BITS   = 960, 
    parameter PAYLOAD_BITS  = 8416,
    parameter CRC_BITS      = 32, 
    parameter PL_RATE = 0,
    parameter DATA_WIDTH = 8)
(
   
    input  wire                      clk,
    input  wire                      rst_n,
    
  
    input  wire                      start_frame,
    
    //  I am using them in Header. Point specified in Assumptions.
    
    // They wont change the functionality just embed some information in Header.
    input  wire [1:0]                frame_type,     
    // Frame sequence number. Also used in PRBS.
    input  wire [15:0]               txfn,           
    
    
    // Payload Interface
    input  wire                      payload_valid,
    input  wire [DATA_WIDTH-1:0]     payload_data,
    input  wire [15:0]               payload_len,    // Payload length in bytes
    
    // Output Interface
    output reg                       busy,
    output reg                       frame_done,
    output reg                       frame_valid,
    output reg  [DATA_WIDTH-1:0]     frame_data
);

    localparam [63:0] PREAMBLE_VALUE = 64'h53225b1d0d73df03;
    // This function is for PL_Rate to Parity byte conversion. This is picked up from the document shared.
    
    function integer get_parity_bytes(input integer rate);
        case (rate)
            0: get_parity_bytes = 0;      // 0 bits / 8
            1: get_parity_bytes = 288;    // 2304 bits / 8
            2: get_parity_bytes = 432;    // 3456 bits / 8
            3: get_parity_bytes = 624;    // 4992 bits / 8
            default: get_parity_bytes = 1152;  // 9216 bits / 8 (PL_RATE=4)
        endcase
    endfunction

 
    localparam PREAMBLE_BYTES = PREAMBLE_BITS / DATA_WIDTH;  // 8 bytes (if DATA_WIDTH=8)
    localparam HEADER_BYTES   = HEADER_BITS / DATA_WIDTH;    // 120 bytes
    localparam PAYLOAD_BYTES  = PAYLOAD_BITS / DATA_WIDTH;   // 1052 bytes
    localparam CRC_BYTES      = CRC_BITS / DATA_WIDTH;       // 4 bytes
    localparam PARITY_BYTES   = get_parity_bytes(PL_RATE);   // 0 to 1152 bytes
    
    localparam TOTAL_BYTES    = PREAMBLE_BYTES + HEADER_BYTES + PAYLOAD_BYTES + CRC_BYTES + PARITY_BYTES;

    
    localparam [2:0] ST_IDLE     = 3'd0;
    localparam [2:0] ST_PREAMBLE = 3'd1;
    localparam [2:0] ST_HEADER   = 3'd2;
    localparam [2:0] ST_PAYLOAD  = 3'd3;
    localparam [2:0] ST_CRC      = 3'd4;
    localparam [2:0] ST_PARITY   = 3'd5;
    localparam [2:0] ST_DONE     = 3'd6;


    reg [2:0]  present_state;
    reg [2:0]  next_state;
    reg [11:0] byte_cnt;           
    
 
    reg [15:0]  payload_len_reg;   
    reg [14:0]  prbs_lfsr;         
    reg [31:0]  crc_reg;           
    reg [959:0] header_reg;       

    // =========================================================================
    // PRBS-15 Generator (for IDLE frame payload fill)
    // Polynomial: x^15 + x^14 + 1 (per Section 3.4.7.1.2)
    // =========================================================================

      wire prbs_bit = prbs_lfsr[14] ^ prbs_lfsr[13];
      wire [14:0] prbs_stream = {prbs_lfsr[13:0], prbs_bit};
      wire [DATA_WIDTH-1:0] prbs_data = (DATA_WIDTH <= 15) ? prbs_stream[14 -: DATA_WIDTH] :
                         {prbs_stream, {(DATA_WIDTH-15){1'b0}}};

    // =========================================================================
    // CRC-32 Calculation Function (IEEE 802.3 polynomial per Table 3-5)
    // Polynomial: 0xEDB88320 (reversed representation)
    // =========================================================================
    function [31:0] crc32_byte;
        input [31:0] crc;
        input [DATA_WIDTH-1:0] data;
        integer i;
        reg [31:0] temp_crc;
        reg [DATA_WIDTH-1:0] temp_data;
        begin
            temp_crc = crc;
            temp_data = data;
            
            for (i = 0; i < DATA_WIDTH; i = i + 1) 
            begin
                if (temp_crc[0] ^ temp_data[0]) 
                begin
                    temp_crc = {1'b0, temp_crc[31:1]} ^ 32'hEDB88320;
                end 
                else 
                begin
                    temp_crc = {1'b0, temp_crc[31:1]};
                end
                temp_data = {1'b0, temp_data[DATA_WIDTH-1:1]};
            end
            
            crc32_byte = temp_crc;
        end
    endfunction


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            present_state <= ST_IDLE;
        else
            present_state <= next_state;
    end


    always @(*) 
    begin
        next_state = present_state;
        
        case (present_state)
            ST_IDLE: begin
                if (start_frame)
                    next_state = ST_PREAMBLE;
            end
            
            ST_PREAMBLE: 
            begin
                if (byte_cnt == PREAMBLE_BYTES - 1)
                    next_state = ST_HEADER;
            end
            
            ST_HEADER: 
            begin
                if (byte_cnt == HEADER_BYTES - 1)
                    next_state = ST_PAYLOAD;
            end
            
            ST_PAYLOAD: 
            begin
                if (byte_cnt == PAYLOAD_BYTES - 1)
                    next_state = ST_CRC;
            end
            
            ST_CRC: 
            begin
                if (byte_cnt == CRC_BYTES - 1) 
                begin
                    if (PARITY_BYTES > 0)
                        next_state = ST_PARITY;
                    else
                        next_state = ST_DONE;
                end
            end
            
            ST_PARITY: 
            begin
                if (byte_cnt == PARITY_BYTES - 1)
                    next_state = ST_DONE;
            end
            
            ST_DONE: 
                    next_state = ST_IDLE;
                        
            default: 
                next_state = ST_IDLE;
            
        endcase
    end

    // Byte Counter - Per-Section 
    // We need to reset when transitioning to new state
  
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            byte_cnt <= 12'd0;
        end 
        else if (present_state != ST_IDLE && present_state != ST_DONE) 
        begin
            // Reset counter when entering new section
            if (present_state != next_state)
                byte_cnt <= 12'd0;
            // Increment within current section
            else if (byte_cnt < 12'd4095)
                byte_cnt <= byte_cnt + 12'd1;
        end 
        else 
        begin
            byte_cnt <= 12'd0;
        end
    end

    // =========================================================================
    // PRBS-15 LFSR Update
    // Seeded with TXFN at frame start, free-runs during frame
    // =========================================================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            prbs_lfsr <= 15'h7FFF;
        end 
        else if (start_frame) 
        begin
            // Seed LFSR with TXFN lower 14 bits + 1 MSB
            prbs_lfsr <= {1'b1, txfn[13:0]};
        end 
        else 
        begin
            // Free-run: feedback from taps 15 and 14
            prbs_lfsr <= {prbs_lfsr[13:0], prbs_bit};
        end
    end

    // =========================================================================
    // Frame Metadata Capture and Header Construction
    // =========================================================================
    always @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n) 
        begin
            payload_len_reg <= 16'd0;
            header_reg <= 960'd0;
            crc_reg <= 32'hFFFFFFFF;
        end 
        else if (start_frame) 
        begin
            // Capture payload length
            payload_len_reg <= payload_len;
            
          header_reg <= {
                
                txfn[7:0],  // Byte 0 (bits [959:952]): d0 = TXFN[7:0] - FIRST OUT
                txfn[15:8], // Byte 1 (bits [951:944]): d1 = TXFN[15:8]                
                16'h0000, 16'h00,  // Byte 2,3,4,5               
                // Byte 6 (bits [911:904]): d6
                // b7=FRAME_TYPE[1], b6-b3=PL_RATE[3:0], b2-b0=ARQ_MAX_RETX[2:0]
                {frame_type[1], PL_RATE[3:0], 3'd0},
                // Byte 7 (bits [903:896]): d7
                // b7-b1=TX_TS[6:0], b0=FRAME_TYPE[0]
                {7'd0, frame_type[0]},
                // Bytes 8-13 (bits [895:856]): d8-d12 = Rest of TX_TS + TOD_SECONDS
                48'h0000000000,
                // Bytes 14-15 (bits [847:832]): d14-d15 = FCCH_PL
                {payload_len[15:8], payload_len[7:0]},
                // Remaining 104 Bytes is zeros
                832'd0
            };
            
            // Initialize CRC-32
            crc_reg <= 32'hFFFFFFFF;
        end 
        else if (present_state == ST_PAYLOAD && payload_valid) 
        begin
            // Update CRC with payload data
            crc_reg <= crc32_byte(crc_reg, payload_data);
        end
    end


    // Frame Output Generation
    
    always @(posedge clk or negedge rst_n)
     begin
        if (!rst_n) 
        begin
            frame_valid <= 1'b0;
            frame_data <= {DATA_WIDTH{1'b0}};
            busy <= 1'b0;
            frame_done <= 1'b0;
        end 
        else 
        begin
            // Default: clear frame_done pulse
            frame_done <= 1'b0;
            
            // Busy when actively generating frame
            busy <= (present_state != ST_IDLE) && (present_state != ST_DONE);
            
            // Frame output logic
            if (present_state != ST_IDLE && present_state != ST_DONE) 
            begin
                frame_valid <= 1'b1;
                case (present_state)
                    
                    ST_PREAMBLE: 
                    begin
                        frame_data <= PREAMBLE_VALUE[PREAMBLE_BITS-1 - byte_cnt*DATA_WIDTH -: DATA_WIDTH];
                    end
                   
                    ST_HEADER: 
                    begin
                        frame_data <= header_reg[HEADER_BITS-1 - byte_cnt*DATA_WIDTH -: DATA_WIDTH];
                    end
                    
                    // Payload: Use payload_data if valid, else fill with PRBS
                    ST_PAYLOAD: 
                    begin
                        frame_data <= (payload_valid && byte_cnt < payload_len_reg) ? payload_data : prbs_data;
                    end
                    
                    // CRC: Output MSB first (network byte order)
                    ST_CRC: 
                    begin
                        frame_data <= crc_reg[CRC_BITS-1 - byte_cnt*DATA_WIDTH -: DATA_WIDTH];
                    end
                    
                    // Parity: Output LDPC parity bits (stub implementation)
                    ST_PARITY: 
                    begin
                        frame_data <= {DATA_WIDTH{1'b0}};  // Zeros for now
                    end
                    
                    default: begin
                        frame_data <= {DATA_WIDTH{1'b0}};
                    end
                endcase
            end 
            else 
            begin
                // Idle: no output
                frame_valid <= 1'b0;
                frame_data <= {DATA_WIDTH{1'b0}};
            end
            
            // Pulse frame_done for one cycle when entering DONE state
            if (present_state == ST_DONE)
                frame_done <= 1'b1;
        end
    end

endmodule