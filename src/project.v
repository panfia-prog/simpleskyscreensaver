/*
 * Tiny Tapeout VGA: Night Phase Only Graphics Generator (Lint-Clean 1x1 Fit)
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,    // ui_in[7:1]: Moon phase selection
    output wire [7:0] uo_out,   // TinyVGA outputs: {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // Unused IO outputs
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // Always 1
    input  wire       clk,      // 24 MHz clock
    input  wire       rst_n     // Active-low reset
);

    // ------------------------------------------------------------------------
    // 1. VGA TIMING & FRAME COUNTER
    // ------------------------------------------------------------------------
    wire hsync, vsync, video_active;
    wire [9:0] pix_x, pix_y;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    reg [7:0] frame_count;
    always @(posedge vsync or negedge rst_n) begin
        if (~rst_n) frame_count <= 8'd0;
        else        frame_count <= frame_count + 1'b1;
    end

    assign uio_oe  = 8'h00;
    assign uio_out = 8'h00;

    // ------------------------------------------------------------------------
    // 2. LOW-GATE PARALLAX BACKGROUND
    // ------------------------------------------------------------------------
    // Truncated adder result to bit [6] to prevent unused bit slice warnings
    wire scroll_y_bit6 = pix_y[6] + frame_count[6]; 
    wire bg_star_a     = (scroll_y_bit6 ^ pix_x[6]) & (pix_y[0] ^ pix_x[0]);
    wire bg_star_b     = (pix_y[5] ^ pix_x[5]) & (pix_y[1] ^ pix_x[1]);

    reg [1:0] bg_R, bg_G, bg_B;
    always @(*) begin
        if (bg_star_a)      {bg_R, bg_G, bg_B} = 6'b00_01_10; // Slate Blue
        else if (bg_star_b) {bg_R, bg_G, bg_B} = 6'b00_00_10; // Dark Blue
        else                {bg_R, bg_G, bg_B} = 6'b00_00_01; // Midnight Blue
    end

    // ------------------------------------------------------------------------
    // 3. ULTRA-LIGHT MOON GENERATOR
    // ------------------------------------------------------------------------
    wire in_moon_box = (pix_x >= 256 && pix_x < 384) && (pix_y >= 176 && pix_y < 304);
    
    // Explicit 4-bit wire slicing [6:3] to prevent lower-bit unused warnings
    wire [3:0] rel_x_hi = pix_x[6:3];
    wire [3:0] rel_y_hi = pix_y[6:3];
    wire corner_clip    = (rel_x_hi[3] == rel_y_hi[3]) && (rel_x_hi[2:0] + rel_y_hi[2:0] < 3);

    wire is_moon_shape = in_moon_box && !corner_clip;

    wire phase_left  = pix_x < 320;
    wire phase_right = pix_x >= 320;
    
    reg is_lit_moon;
    always @(*) begin
        if (!is_moon_shape) begin
            is_lit_moon = 1'b0;
        end else if (ui_in[7]) begin
            is_lit_moon = 1'b1; // Full Moon
        end else if (ui_in[6]) begin
            is_lit_moon = phase_right; // First Quarter
        end else if (ui_in[5]) begin
            is_lit_moon = phase_left; // Last Quarter
        end else begin
            is_lit_moon = (pix_x[4:3] == 2'b10); // Crescent strip approximation
        end
    end

    // ------------------------------------------------------------------------
    // 4. MINIMAL 2-STAR REGISTER ENGINE
    // ------------------------------------------------------------------------
    reg [15:0] lfsr;
    reg [9:0]  star_pos  [0:1];
    reg [2:0]  star_life [0:1];

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            lfsr         <= 16'hACE1;
            star_pos[0]  <= 10'd0;
            star_pos[1]  <= 10'd0;
            star_life[0] <= 3'd0;
            star_life[1] <= 3'd0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13]};

            if (pix_x == 10'd0 && pix_y == 10'd0) begin
                if (star_life[0] == 0 && lfsr[0]) begin
                    star_pos[0]  <= lfsr[9:0];
                    star_life[0] <= 3'd7;
                end else if (star_life[0] > 0) begin
                    star_life[0] <= star_life[0] - 1'b1;
                end

                if (star_life[1] == 0 && !lfsr[0]) begin
                    star_pos[1]  <= lfsr[15:6];
                    star_life[1] <= 3'd7;
                end else if (star_life[1] > 0) begin
                    star_life[1] <= star_life[1] - 1'b1;
                end
            end
        end
    end

    wire [9:0] curr_cell = {pix_y[8:4], pix_x[8:4]};
    wire is_star = ((star_life[0] > 0 && star_pos[0] == curr_cell) ||
                    (star_life[1] > 0 && star_pos[1] == curr_cell)) &&
                   (pix_x[3:2] == 2'b01 && pix_y[3:2] == 2'b01) && !is_lit_moon;

    // ------------------------------------------------------------------------
    // 5. FINAL COLOR COMPOSITION
    // ------------------------------------------------------------------------
    reg [1:0] R, G, B;

    always @(*) begin
        if (!video_active) begin
            {R, G, B} = 6'b00_00_00; // Blanking
        end else if (is_lit_moon) begin
            {R, G, B} = 6'b11_11_00; // Yellow Moon
        end else if (is_star) begin
            {R, G, B} = 6'b11_11_11; // White Twinkle Stars
        end else begin
            {R, G, B} = {bg_R, bg_G, bg_B}; // Parallax Sky
        end
    end

    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

    wire _unused_ok = &{ena, uio_in, ui_in[4:0]};

endmodule
