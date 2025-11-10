`timescale 1ns/1ps
/*
I2C Master TX модуль
- Генерує SCL
- Передає 8-бітні дані на SDA
*/
module i2c_master_tx(
    input clk,            // системний тактовий сигнал
    input rst_n,          // активний низький скидання
    input start,          // початок передачі
    input [6:0] slave_addr, // адреса Slave
    input [7:0] tx_data,  // дані для передачі
    inout sda,            // лінія даних I2C
    output reg scl,       // тактовий сигнал I2C
    output reg busy       // Master зайнятий передачею
);

    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg sda_out;

    assign sda = sda_out ? 1'bz : 1'b0; // open-drain

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            scl <= 1;
            sda_out <= 1;
            busy <= 0;
            bit_cnt <= 0;
        end else if(start) begin
            busy <= 1;
            shift_reg <= tx_data;
            scl <= ~scl;
            if(scl) begin
                sda_out <= shift_reg[7-bit_cnt];
                bit_cnt <= bit_cnt + 1;
                if(bit_cnt == 7) begin
                    bit_cnt <= 0;
                    busy <= 0;
                end
            end
        end else begin
            busy <= 0;
            sda_out <= 1;
        end
    end

endmodule
