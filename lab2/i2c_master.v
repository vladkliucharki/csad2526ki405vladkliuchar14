// Module I2C Master (Variant 14)
// Language: Verilog
// This module coordinates the I2C protocol: Start, Stop, Transmit, Receive, ACK/NACK.
module i2c_master (
    // ---- Global Signals ----
    input wire clk,
    input wire reset,

    // ---- Control Interface ----
    input wire i_start_tx,        // Command: "Start Operation"
    input wire [6:0] i_address,   // 7-bit Slave Address
    input wire i_rw_mode,         // 0 = Write, 1 = Read
    output reg o_done,            // Flag: Operation complete
    output reg o_ack_error,       // Flag: ACK bit was not received (1)
    
    // ---- Data Interface ----
    output reg [7:0] o_rx_data,   // Received data byte
    output reg o_rx_data_valid,   // Pulse high when o_rx_data is valid
    
    // ---- I2C Lines (Tri-state SDA) ----
    output reg o_scl,
    input wire i_sda,              // Read data from SDA
    output reg o_sda_out,          // Data to drive onto SDA (if enabled)
    output reg o_sda_oe            // Output Enable: 1=Master drives SDA, 0=Master listens
);

    // ---- Parameters ----
    localparam CLK_DIV_RATIO = 250; // 50MHz clk -> 100kHz SCL
    
    // ---- FSM State Parameters ----
    localparam S_IDLE       = 4'b0000;
    localparam S_START      = 4'b0001;
    localparam S_TX_BYTE    = 4'b0010;
    localparam S_ACK_CHK    = 4'b0011;
    localparam S_STOP       = 4'b0100;
    localparam S_RX_BYTE    = 4'b0110;
    localparam S_TX_NACK    = 4'b0111;
    
    // ---- FSM Internal Registers ----
    reg [3:0] state_reg = S_IDLE;
    reg [$clog2(CLK_DIV_RATIO):0] clk_div_counter = 0;
    reg [3:0] bit_counter = 0;
    
    // --- Internal Triggers for TX/RX Module ---
    reg tx_load_reg;
    reg tx_shift_trigger_reg;
    reg rx_sample_trigger_reg; // Новий тригер для захоплення Rx біта
    
    // --- Internal Wires for module communication ---
    wire w_tx_bit;
    wire [7:0] w_rx_byte_from_module;
    wire w_data_dir_tx;

    // ---- 1. Instantiate Transmitter/Receiver (Tx/Rx) Module ----
    i2c_tx_rx u_tx_rx (
        .clk(clk),
        .reset(reset),
        
        // TX Interface
        .i_load_tx_byte(tx_load_reg),
        .i_tx_byte({i_address, i_rw_mode}), // Адреса + R/W біт
        .i_shift_bit(tx_shift_trigger_reg),
        .o_tx_bit(w_tx_bit),
        
        // RX Interface
        .i_sample_bit(rx_sample_trigger_reg), // Тригер для захоплення
        .i_sda_bit(i_sda),                    // Вхід SDA для захоплення
        .o_rx_byte(w_rx_byte_from_module)     // Вихід отриманого байта
    );

    // ---- Main Logic Block (FSM) ----
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_reg       <= S_IDLE;
            o_scl           <= 1;
            o_sda_oe        <= 0; 
            o_sda_out       <= 0;
            o_done          <= 0;
            o_ack_error     <= 0;
            bit_counter     <= 0;
            clk_div_counter <= 0;
            tx_load_reg     <= 0;
            tx_shift_trigger_reg <= 0;
            rx_sample_trigger_reg <= 0;
            o_rx_data       <= 8'h00;
            o_rx_data_valid <= 0;
        end else begin
            
            // Скидання тригерів за замовчуванням
            tx_load_reg     <= 0;
            tx_shift_trigger_reg <= 0;
            rx_sample_trigger_reg <= 0;
            o_done          <= 0;
            o_ack_error     <= 0;
            o_rx_data_valid <= 0;
            
            // Clock Divider Logic
            if (clk_div_counter < CLK_DIV_RATIO - 1) begin
                clk_div_counter <= clk_div_counter + 1;
            end else begin
                clk_div_counter <= 0;
            end
            
            // FSM Logic
            case (state_reg)
                
                S_IDLE: begin
                    o_scl <= 1;
                    o_sda_oe <= 0; 
                    
                    if (i_start_tx) begin
                        state_reg <= S_START;
                        tx_load_reg <= 1; // Завантажити {Адресу, R/W}
                        clk_div_counter <= 0;
                    end
                end
                
                S_START: begin
                    o_sda_out <= 0;
                    o_sda_oe <= 1;  
                    
                    if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_sda_out <= w_tx_bit;
                        state_reg <= S_TX_BYTE;
                        o_scl <= 0; 
                        clk_div_counter <= 0;
                        bit_counter <= 8; // Лічильник для 8 біт адреси
                    end
                end
                
                S_TX_BYTE: begin
                    if (bit_counter > 0) begin
                        
                        if (clk_div_counter == 0) begin
                            o_sda_out <= w_tx_bit; 
                            o_sda_oe <= 1'b1;
                        end
                        
                        else if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                            o_scl <= 1;
                            tx_shift_trigger_reg <= 1; // Команда на зсув
                        end 
                        
                        else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                            o_scl <= 0;
                            bit_counter <= bit_counter - 1;
                        end
                        
                    end else begin
                        // Закінчили 8 біт, перевіряємо ACK
                        state_reg <= S_ACK_CHK;
                        clk_div_counter <= 0;
                        o_scl <= 0; 
                        o_sda_oe <= 0; // Майстер відпускає SDA для ACK
                    end
                end
                
                S_ACK_CHK: begin
                    if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                        o_scl <= 1;
                        if (i_sda == 1'b1) begin // NACK
                            o_ack_error <= 1;
                        end
                    end 
                    
                    else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_scl <= 0; 
                        
                        if (o_ack_error) begin
                            state_reg <= S_STOP; // Помилка, зупинка
                        end else begin
                            // ACK отримано, перевіряємо режим
                            if (i_rw_mode == 1'b1) begin 
                                // Режим ЧИТАННЯ: перехід до прийому байта
                                state_reg <= S_RX_BYTE;
                                bit_counter <= 8; // Готуємося прийняти 8 біт
                            end else begin
                                // Режим ЗАПИСУ: (тут можна додати S_TX_DATA_BYTE)
                                // Поки що просто зупиняємось
                                state_reg <= S_STOP; 
                            end
                        end
                    end
                end
                
                // ==========================================================
                // ==== ПОЧАТОК ФІНАЛЬНОГО ВИПРАВЛЕННЯ S_RX_BYTE ====
                // ==========================================================
                S_RX_BYTE: begin
                    if (bit_counter > 0) begin
                        
                        // SCL 'high'
                        if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                            o_scl <= 1;
                        end
                        
                        // ФІНАЛЬНЕ ВИПРАВЛЕННЯ:
                        // Зчитуємо біт у 3/4 SCL-циклу (гарантовано стабільний)
                        else if (clk_div_counter == (CLK_DIV_RATIO * 3 / 4) - 1) begin
                            rx_sample_trigger_reg <= 1; // Pulse
                        end

                        // SCL 'low'
                        else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                            o_scl <= 0;
                            bit_counter <= bit_counter - 1;
                        end

                    end else begin
                        // Закінчили 8 біт, перехід до відправки NACK
                        state_reg <= S_TX_NACK;
                        clk_div_counter <= 0;
                        o_scl <= 0; 
                        o_rx_data <= w_rx_byte_from_module; // Зберегти отриманий байт
                        o_rx_data_valid <= 1; // Повідомити, що дані готові
                    end
                end
                // ==========================================================
                // ==== КІНЕЦЬ ВИПРАВЛЕНОГО БЛОКУ ====
                // ==========================================================

                S_TX_NACK: begin
                    // Майстер відправляє NACK (логічна '1'), щоб зупинити читання
                    
                    if (clk_div_counter == 0) begin
                        o_sda_out <= 1'b1; // NACK
                        o_sda_oe <= 1'b1;
                    end
                    
                    else if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                        o_scl <= 1; // Раб читає NACK
                    end 
                    
                    else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_scl <= 0;
                        state_reg <= S_STOP; // Перехід до STOP
                    end
                end

                S_STOP: begin
                    // I2C Stop Condition: SCL=1, SDA 0->1
                    
                    // 1. Примусово SDA low (поки SCL low)
                    if (clk_div_counter == 0) begin
                        o_sda_out <= 0;
                        o_sda_oe <= 1;
                    end

                    // 2. SCL high
                    else if (clk_div_counter == (CLK_DIV_RATIO / 2) - 1) begin
                        o_scl <= 1;
                    end 
                    
                    // 3. SDA high (поки SCL high) -> STOP
                    else if (clk_div_counter == (CLK_DIV_RATIO / 2)) begin
                         o_sda_out <= 1; 
                    end
                    
                    // 4. Кінець, відпустити шину
                    else if (clk_div_counter == CLK_DIV_RATIO - 1) begin
                        o_sda_oe <= 0; // Відпустити SDA
                        state_reg <= S_IDLE;
                        o_done <= 1; 
                    end
                end
                
                default: begin
                    state_reg <= S_IDLE;
                end
                
            endcase
        end
    end

endmodule