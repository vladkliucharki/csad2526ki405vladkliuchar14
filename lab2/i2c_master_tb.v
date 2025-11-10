// Testbench for i2c_master (Variant 14) - with Rx support
`timescale 1ns / 1ps

module i2c_master_tb;

    // ---- Test Parameters ----
    localparam CLK_PERIOD = 20; // 50 MHz clock
    localparam SLAVE_TX_DATA = 8'hC3; // Data the slave will return on read

    // ---- Signals to connect to the UUT (Unit Under Test) ----
    reg clk_tb;
    reg reset_tb;
    reg i_start_tx_tb;
    
    reg [6:0] i_address_tb;
    reg i_rw_mode_tb;
    
    wire o_done_tb;
    wire o_ack_error_tb;
    
    wire [7:0] o_rx_data_tb;
    wire o_rx_data_valid_tb;
    
    wire o_scl_tb;
    wire o_sda_out_tb; 
    wire o_sda_oe_tb;
    
    // --- SDA Bus Model ---
    reg i_sda_val; // Value driven by the slave
    wire i_sda_tb; // Actual value on the SDA bus
    
    // --- Edge Detection Registers ---
    reg prev_o_scl_tb = 0;
    reg prev_i_sda_tb = 1;
    
    // --- Logging Registers ---
    reg [7:0] final_rx_byte = 0; // Logs the byte received by the slave
    reg ack_msg_printed = 0; 
    reg [7:0] next_rx_byte; // Temp register for shifting

    // --- SDA Bus Model ---
    // Multiplexes SDA line: master drives if o_sda_oe_tb is high, slave (i_sda_val) drives if low.
    assign i_sda_tb = (o_sda_oe_tb) ? o_sda_out_tb : i_sda_val;


    // ---- 1. Instantiate the Unit Under Test (UUT) ----
    i2c_master uut (
        .clk(clk_tb),
        .reset(reset_tb),
        .i_start_tx(i_start_tx_tb),
        .i_address(i_address_tb),
        .i_rw_mode(i_rw_mode_tb),
        .o_done(o_done_tb),
        .o_ack_error(o_ack_error_tb),
        .o_rx_data(o_rx_data_tb),
        .o_rx_data_valid(o_rx_data_valid_tb),
        .o_scl(o_scl_tb),
        .i_sda(i_sda_tb),
        .o_sda_out(o_sda_out_tb),
        .o_sda_oe(o_sda_oe_tb)
    );

    // --- Clock Generation & Edge Registers Update ---
    initial begin 
        clk_tb = 0;
    end
    always begin 
        # (CLK_PERIOD / 2) clk_tb = ~clk_tb;
    end
    
    // Store previous SCL/SDA values to detect edges
    always @(posedge clk_tb) begin
        if (reset_tb) begin
            prev_o_scl_tb <= 0;
            prev_i_sda_tb <= 1;
        end else begin
            prev_o_scl_tb <= o_scl_tb;
            prev_i_sda_tb <= i_sda_tb;
        end
    end

    // ===================================================================
    // ==== SLAVE MODEL BLOCK ====
    // ===================================================================
    reg [3:0] bit_count_slave = 0; // Counts incoming bits (address)
    reg [7:0] rx_byte_slave = 0; // Shift register for incoming byte
    reg slave_active = 0; // Slave is active after START
    reg slave_is_read_op = 0; // Slave is in read mode (master reading)
    reg [3:0] slave_tx_bit_count = 8; // Counts outgoing bits (data)
    reg [7:0] slave_tx_reg = SLAVE_TX_DATA; // Data to be sent by slave

    // ---- 1. Sequential Logic (State Update) ----
    always @(posedge clk_tb or posedge reset_tb) begin
        if (reset_tb) begin
            slave_active <= 0;
            bit_count_slave <= 0;
            final_rx_byte <= 0;
            ack_msg_printed <= 0;
            slave_is_read_op <= 0;
            slave_tx_bit_count <= 8;
            slave_tx_reg <= SLAVE_TX_DATA;
        end else begin
            
            // --- Detect START Condition (SDA falling edge while SCL is high) ---
            if (o_scl_tb == 1 && prev_i_sda_tb == 1 && i_sda_tb == 0) begin
                $display("@%0t: Slave detected START condition.", $time);
                slave_active <= 1;
                bit_count_slave <= 8; // Expect 8 bits (Addr+R/W)
                rx_byte_slave <= 0; 
                ack_msg_printed <= 0;
                slave_is_read_op <= 0;
                slave_tx_bit_count <= 8;
                slave_tx_reg <= SLAVE_TX_DATA;
            end
            
            // --- Sample Data (on SCL rising edge) ---
            if (slave_active && !prev_o_scl_tb && o_scl_tb) begin
                 if (bit_count_slave > 0) begin
                     // A. Receiving Address+R/W byte
                     next_rx_byte = (rx_byte_slave << 1) | i_sda_tb;
                     rx_byte_slave <= next_rx_byte;
                     bit_count_slave <= bit_count_slave - 1;
                     
                     if (bit_count_slave == 1) begin
                         slave_is_read_op <= i_sda_tb; // Store the R/W bit
                     end
                     $display("@%0t: Slave sampled bit %0d: %b. Register: %h.", $time, 8 - bit_count_slave + 1, i_sda_tb, next_rx_byte);
                 
                 end else if (slave_is_read_op && slave_tx_bit_count == 0) begin
                     // C. Master sent NACK (to stop reading)
                     if (i_sda_tb == 1'b1) begin
                         $display("@%0t: Slave received NACK from master. Releasing bus.", $time);
                     end
                     slave_is_read_op <= 0; // Stop transmitting
                 end
            end
            
            // --- ACK Flag Logic ---
            // Set flag after 8th bit is sampled, while SCL is low (preparing for ACK)
            if (slave_active && bit_count_slave == 0 && !ack_msg_printed && o_scl_tb == 0 && o_sda_oe_tb == 0) begin
                 $display("@%0t: Slave ACK: pulling SDA low.", $time);
                 ack_msg_printed <= 1; // Mark that ACK has been handled
            end

            // --- TX Register Shift Logic (Sending Data) ---
            // Shift data out on SCL falling edge, so it's stable for next rising edge
            if (slave_is_read_op && ack_msg_printed && slave_tx_bit_count > 0) begin
                if (prev_o_scl_tb && !o_scl_tb) begin // On SCL falling edge
                    $display("@%0t: Slave TX bit %0d: %b (sent)", $time, 8 - slave_tx_bit_count + 1, slave_tx_reg[7]);
                    slave_tx_reg <= slave_tx_reg << 1;
                    slave_tx_bit_count <= slave_tx_bit_count - 1;
                end
            end
            
            // --- Detect STOP Condition (SDA rising edge while SCL is high) ---
            if (o_scl_tb == 1 && !prev_i_sda_tb && i_sda_tb && slave_active) begin
                final_rx_byte <= rx_byte_slave; // Log the received byte
                $display("@%0t: Slave detected STOP condition. Final Address Byte: %h", $time, rx_byte_slave);
                slave_active <= 0; // Reset slave state
                rx_byte_slave <= 0;
            end
        end
    end
    
    // ---- 2. Combinational Logic (Driving i_sda_val) ----
    always @(*) begin
        i_sda_val = 1'b1; // Default: release bus (pull-up high)
        
        if (slave_active) begin
            // --- ACK Logic ---
            // Slave pulls SDA low for ACK during the 9th SCL pulse (low phase)
            if (bit_count_slave == 0 && !ack_msg_printed && o_scl_tb == 0 && o_sda_oe_tb == 0) begin
                i_sda_val = 1'b0;
            end
            // --- TX Data Logic ---
            // Slave drives the bus with its data bit
            else if (slave_is_read_op && ack_msg_printed && slave_tx_bit_count > 0) begin
                i_sda_val = slave_tx_reg[7]; // Drive MSB
            end
        end
    end
    // ===================================================================
    // ==== END OF SLAVE MODEL BLOCK ====
    // ===================================================================


    // ===================================================================
    // ==== TEST SEQUENCE (INITIAL BLOCK) ====
    // ===================================================================
    
    reg [7:0] captured_rx_data_tb = 8'hXX; // Register to capture UUT output
    

    // ---- 4. Test Sequence ----
    initial begin
        // --- Initialization ---
        reset_tb       <= 1;
        i_start_tx_tb  <= 0;
        i_address_tb   <= 7'h00;
        i_rw_mode_tb   <= 0;
        
        # (CLK_PERIOD * 5);
        reset_tb <= 0;
        # (CLK_PERIOD * 10);
        
        // --- TEST 1: Send Address+Write 0xA0 (1010 0000) ---
        $display("TEST 1: Sending Address+Write 0xA0...");
        i_address_tb <= 7'h50; // 1010000
        i_rw_mode_tb <= 0;     // 0
        i_start_tx_tb <= 1;

        # CLK_PERIOD;
        i_start_tx_tb <= 0;

        wait (o_done_tb == 1);
        
        $display("TEST 1: Done flag received. Sent Addr: 0xA0, Received by Slave: %h, ACK Error: %b", final_rx_byte, o_ack_error_tb);
        if (o_ack_error_tb == 0 && final_rx_byte == 8'hA0) begin
            $display("TEST 1: SUCCESS - ACK received and data 0xA0 verified.");
        end else begin
            $display("TEST 1: FAILURE - NACK received or data mismatch. Expected 0xA0, received %h", final_rx_byte);
        end

        # (CLK_PERIOD * 20); // Wait between tests
        
        // --- TEST 2: Send Address+Read 0xA1 (1010 0001) ---
        $display("TEST 2: Sending Address+Read 0xA1 (Expecting 0xC3)...");
        captured_rx_data_tb <= 8'hXX; // Reset capture register
        i_address_tb <= 7'h50; // 1010000
        i_rw_mode_tb <= 1;     // 1
        i_start_tx_tb <= 1;

        # CLK_PERIOD;
        i_start_tx_tb <= 0;
        
        wait (o_done_tb == 1);
        
        $display("TEST 2: Done flag received. Sent Addr: 0xA1, Received by Slave: %h, ACK Error: %b", final_rx_byte, o_ack_error_tb);
        
        // Note: Logic to check 'captured_rx_data_tb' against 'SLAVE_TX_DATA'
        // would go here, triggered by 'o_rx_data_valid_tb'.
        // This testbench currently only checks slave reception.

        # (CLK_PERIOD * 20);
        
        $display("Simulation Finished.");
        $stop;
    end

endmodule