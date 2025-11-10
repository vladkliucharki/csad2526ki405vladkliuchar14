`timescale 1ns/1ps
/*
I2C Master RX модуль
- Читає 8-бітні дані від Slave
- Генерує SCL
*/
module i2c_master_rx(
    input clk,
    input rst_n,
    input start,
    inout sda,
    output reg scl,
    output reg [7:0] rx_data,
    output reg data_ready,
    output reg busy
);
parameter CLK_DIV_HALF = 5; 
reg [3:0] clk_div_cnt; 

reg [3:0] bit_cnt;
reg [7:0] shift_reg;

// Master BUSY Logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        busy <= 0;
    else if (start) 
        busy <= 1;
    else if (data_ready) 
        busy <= 0;
end

// I2C SCL Clock Generator
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl <= 1'b1;
        clk_div_cnt <= 0;
    end else if (busy) begin
        if (clk_div_cnt == CLK_DIV_HALF - 1) begin
            scl <= ~scl;
            clk_div_cnt <= 0;
        end else begin
            clk_div_cnt <= clk_div_cnt + 1;
        end
    end else begin
        scl <= 1'b1; 
        clk_div_cnt <= 0;
    end
end

// I2C Data Sampling Logic (Прийом 8 біт)
always @(posedge scl or negedge rst_n) begin
    if(!rst_n) begin
        bit_cnt <= 0;
        shift_reg <= 0;
        rx_data <= 0; 
        data_ready <= 0; 
    end else begin
        if (!busy) begin
            data_ready <= 0;
        end 
        
        if(busy) begin 
            // Зчитуємо біт (bit_cnt 0..7)
            #15 shift_reg[7-bit_cnt] <= sda;

            if(bit_cnt == 7) begin
                // Завершення: Після прийому 8-го біта
                rx_data <= shift_reg;
                data_ready <= 1; 
                bit_cnt <= 0; 
            end else begin
                // Продовження: Інкрементуємо для наступного біта (0..6)
                bit_cnt <= bit_cnt + 1;
            end
        end
    end
end

endmodule