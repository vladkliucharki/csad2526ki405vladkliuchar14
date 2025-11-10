// Module I2C Master (Variant 14)
// Language: Verilog
// This module coordinates the I2C protocol: Start, Stop, Transmit, Receive, ACK/NACK.
module i2c_master (
    // ---- Global Signals ----
    input wire clk,
    input wire reset,

    // ---- Control Interface ----
    input wire i_start_tx,       // Command: "Start Operation"
    input wire [6:0] i_address,    // 7-bit Slave Address
    input wire i_rw_mode,          // 0 = Write, 1 = Read
    output reg o_done,             // Flag: Operation complete
    output reg o_ack_error,        // Flag: ACK bit was not received (1)
    
    // ---- Data Interface ----
    output reg [7:0] o_rx_data,    // Received data byte
    output reg o_rx_data_valid,    // Pulse high when o_rx_data is valid
    
    // ---- I2C Lines (Tri-state SDA) ----
    output reg o_scl,
    input wire i_sda,              // Read data from SDA
    output reg o_sda_out,           // Data to drive onto SDA (if enabled)
    output reg o_sda_oe             // Output Enable: 1=Master drives SDA, 0=Master listens
);

    // ---- Parameters ----
    localparam CLK_DIV_RATIO = 250; // 50MHz clk -> 100kHz SCL
    
    // ---- FSM State Parameters ----
    localparam S_IDLE        = 4'b0000;
    localparam S_START       = 4'b0001;
    localparam S_TX_BYTE     = 4'b0010;
    localparam S_ACK_CHK     = 4'b0011;
    localparam S_STOP        = 4'b0100;
    localparam S_RX_BYTE     = 4'b0110;
    localparam S_TX_NACK     = 4'b0111;
    
    // ---- FSM Internal Registers ----
    reg [3:0] state_reg = S_IDLE;
    reg [$clog2(CLK_DIV_RATIO):0] clk_div_counter = 0; // SCL clock divider counter
    reg [3:0] bit_counter = 0; // Counts bits for Tx/Rx
    
    // --- Internal Triggers for TX/RX Module ---
    reg tx_load_reg; // Pulse to load the Tx shift register
    reg tx_shift_trigger_reg; // Pulse to shift the Tx register
    reg rx_sample_trigger_reg; // Pulse to sample the Rx bit
    
    // --- Internal Wires for module communication ---
    wire w_tx_bit; // Transmitted bit from the Tx/Rx module
    wire [7:0] w_rx_byte_from_module; // Received byte from the Tx/Rx module
    wire w_data_dir_tx; // (Unused)

    // ---- 1. Instantiate Transmitter/Receiver (Tx/Rx) Module ----
    i2c_tx_rx u_tx_rx (
        .clk(clk),
        .reset(reset),
        
        // TX Interface
        .i_load_tx_byte(tx_load_reg),
        .i_tx_byte({i_address, i_rw_mode}), // Combine Address and R/W bit
        .i_shift_bit(tx_shift_trigger_reg),
        .o_tx_bit(w_tx_bit),
        
        // RX Interface
        .i_sample_bit(rx_sample_trigger_reg), // Latch trigger
        .i_sda_bit(i_sda),                 // SDA input for sampling
        .o_rx_byte(w_rx_byte_from_module)    // Output of received byte
    );

    // ---- Main Logic Block (FSM) ----
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // --- Reset all state registers and outputs ---
            state_reg           <= S_IDLE;
            o_scl               <= 1; // SCL high (idle)
            o_sda_oe            <= 0; // SDA released (high-Z)
            o_sda_out           <= 0;
            o_done              <= 0;
            o_ack_error         <= 0;
            bit_counter         <= 0;
            clk_div_counter     <= 0;
            tx_load_reg         <= 0;
            tx_shift_trigger_reg <= 0;
            rx_sample_trigger_reg <= 0;
            o_rx_data           <= 8'h00;
            o_rx_data_valid     <= 0;
        end else begin
            
            // --- Default assignments (to avoid latches) ---
            tx_load_reg           <= 0;
            tx_shift_trigger_reg  <= 0;
            rx_sample_trigger_reg <= 0;
            o_done                <= 0;
            o_ack_error           <= 0;
            o_rx_data_valid       <= 0;
            
            // --- Clock Divider Logic ---
            // Generates the SCL frequency
            if (clk_div_counter < CLK_DIV_RATIO - 1) begin
                clk_div_counter <= clk_div_counter + 1;
            end else begin
                clk_div_counter <= 0;
            end
            
            // --- FSM Logic ---
            case (state_reg)
                
                S_IDLE: begin
                    o_scl <= 1; // Keep SCL high
                    o_sda_oe <= 0; // Keep SDA released
                    
                    if (i_start_tx) begin
                        state_reg <= S_START;
                        tx_load_reg <= 1; // Load {Address, R/W} into shift register
                        clk_div_counter <= 0; // Reset divider for START timing
                    end
                end
                
                S_START: begin
                    // --- I2C START Condition ---
                    // SCL is high (from IDLE), bring SDA low
                    o_sda_out <= 0;
                    o_sda_oe <= 1; // Drive SDA low
                    
                    // Wait for clock divider to roll over
                    if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_sda_out <= w_tx_bit; // Pre-load first bit
                        state_reg <= S_TX_BYTE;
                        o_scl <= 0; // Bring SCL low for first bit
                        clk_div_counter <= 0;
                        bit_counter <= 8; // Counter for 8 bits (Addr+R/W)
                    end
                end
                
                S_TX_BYTE: begin
                    if (bit_counter > 0) begin
                        // --- Transmit 8 bits ---
                        
                        // SCL low phase (start of cycle)
                        if (clk_div_counter == 0) begin
                            o_sda_out <= w_tx_bit; // Set data bit
                            o_sda_oe <= 1'b1; // Drive SDA
                        end
                        
                        // SCL high phase (middle of cycle)
                        else if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                            o_scl <= 1; // Bring SCL high
                            tx_shift_trigger_reg <= 1; // Command: shift for next bit
                        end 
                        
                        // SCL low phase (end of cycle)
                        else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                            o_scl <= 0; // Bring SCL low
                            bit_counter <= bit_counter - 1; // Decrement bit counter
                        end
                        
                    end else begin
                        // --- 8 bits sent, check for ACK ---
                        state_reg <= S_ACK_CHK;
                        clk_div_counter <= 0;
                        o_scl <= 0; 
                        o_sda_oe <= 0; // Master releases SDA for ACK
                    end
                end
                
                S_ACK_CHK: begin
                    // --- Check for ACK bit from slave ---
                    
                    // SCL high phase (middle of cycle)
                    if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                        o_scl <= 1; // Bring SCL high
                        if (i_sda == 1'b1) begin // Read SDA
                            o_ack_error <= 1; // NACK received
                        end
                    end 
                    
                    // SCL low phase (end of cycle)
                    else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_scl <= 0; 
                        
                        if (o_ack_error) begin
                            state_reg <= S_STOP; // Error, go to STOP
                        end else begin
                            // ACK received, check R/W mode
                            if (i_rw_mode == 1'b1) begin 
                                // READ Mode: transition to receiving a byte
                                state_reg <= S_RX_BYTE;
                                bit_counter <= 8; // Prepare to receive 8 bits
                            end else begin
                                // WRITE Mode: (Data byte TX not implemented)
                                // For now, just stop
                                state_reg <= S_STOP; 
                            end
                        end
                    end
                end
                
                S_RX_BYTE: begin
                    if (bit_counter > 0) begin
                        
                        // SCL 'high'
                        if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                            o_scl <= 1;
                        end
                        
                        // Sample the bit at 3/4 of the SCL cycle
                        // This ensures data is stable
                        else if (clk_div_counter == (CLK_DIV_RATIO * 3 / 4) - 1) begin
                            rx_sample_trigger_reg <= 1; // Pulse
                        end

                        // SCL 'low'
                        else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                            o_scl <= 0;
                            bit_counter <= bit_counter - 1;
                        end

                    end else begin
                        // --- 8 bits received, transition to sending NACK ---
                        state_reg <= S_TX_NACK;
                        clk_div_counter <= 0;
                        o_scl <= 0; 
                        o_rx_data <= w_rx_byte_from_module; // Store the received byte
                        o_rx_data_valid <= 1; // Flag that data is valid
                    end
                end

                S_TX_NACK: begin
                    // Master sends NACK ('1') to stop slave transmission
                    
                    // SCL low phase (start of cycle)
                    if (clk_div_counter == 0) begin
                        o_sda_out <= 1'b1; // NACK
                        o_sda_oe <= 1'b1; // Drive SDA high
                    end
                    
                    // SCL high phase (middle of cycle)
                    else if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                        o_scl <= 1; // Slave reads NACK
                    end 
                    
                    // SCL low phase (end of cycle)
                    else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_scl <= 0;
                        state_reg <= S_STOP; // Transition to STOP
                    end
                end

                S_STOP: begin
                    // --- I2C Stop Condition: SCL=1, SDA 0->1 ---
                    
                    // 1. Force SDA low (while SCL is low)
                    if (clk_div_counter == 0) begin
                        o_sda_out <= 0;
                        o_sda_oe <= 1;
                    end

                    // 2. SCL high
                    else if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                        o_scl <= 1;
                    end 
                    
                    // 3. SDA high (while SCL is high) -> STOP
                    else if (clk_div_counter == (CLK_DIV_RATIO / 2)) begin
                         o_sda_out <= 1; 
                    end
                    
                    // 4. End, release bus
                    else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_sda_oe <= 0; // Release SDA
                        state_reg <= S_IDLE;
                        o_done <= 1; // Signal operation complete
                    end
                end
                
                default: begin
                    state_reg <= S_IDLE;
                end
                
            endcase
        end
    end

endmodule