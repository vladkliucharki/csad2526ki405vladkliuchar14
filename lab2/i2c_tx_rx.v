	// Module: i2c_tx_rx
	// Description: Handles 8-bit shift/sample register logic (MSB first).
	module i2c_tx_rx (
		 // ---- Global Signals ----
		 input wire clk,
		 input wire reset,

		 // ---- TX Interface (Inputs from FSM) ----
		 input wire i_load_tx_byte,   // Load i_tx_byte into tx_register
		 input wire [7:0] i_tx_byte,  // Byte to transmit
		 input wire i_shift_bit,      // Shift tx_register left 
		 output wire o_tx_bit,        // Current bit (MSB) to drive onto SDA

		 // ---- RX Interface (Inputs from FSM) ----
		 input wire i_sample_bit,     // Trigger to sample i_sda_bit
		 input wire i_sda_bit,        // The SDA line to be sampled
		 output wire [7:0] o_rx_byte  // Received byte
	);
		 // Internal Register for Transmitting
		 reg [7:0] tx_register = 8'h00;
		 
		 // Internal Registers for Receiving
		 reg [7:0] rx_register = 8'h00;
		 
		 // Output the Most Significant Bit (MSB) for transmission
		 assign o_tx_bit = tx_register[7];
		 
		 // Output the received byte
		 assign o_rx_byte = rx_register;
		 
		 // Main Logic for Shift/Sample Register
		 always @(posedge clk or posedge reset) begin
			  if (reset) begin
					tx_register <= 8'h00;
					rx_register <= 8'h00;
			  end else begin
					
					// 1. Load TX data
					if (i_load_tx_byte) begin
						 tx_register <= i_tx_byte;
					// 2. Shift TX data (MSB first)
					end else if (i_shift_bit) begin
						 tx_register <= tx_register << 1;
					end
					
	// 3. Sample RX data (MSB first)
					if (i_sample_bit) begin
						 rx_register <= {rx_register[6:0], i_sda_bit};
					end

			  end
		 end

	endmodule