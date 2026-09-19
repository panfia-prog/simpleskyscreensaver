/*
 * Tiny Tapeout VGA: Night Phase Only Graphics Generator (Synthesis-Optimized)
 * - Night Phase: Interactive moon phases, vertical parallax sky, and twinkling colored stars
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_panfia_sky (
    input  wire [7:0] ui_in,    // ui_in[7:1]: Priority Moon Phase Selection
    output wire [7:0] uo_out,   // TinyVGA outputs: {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]}
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // Unused IO outputs
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // Always 1
    input  wire       clk,      // 24 MHz clock
    input  wire       rst_n     // Active-low reset
);

    // ------------------------------------------------------------------------
    // 1. VGA SIGNAL GENERATION & FRAME COUNTER
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

    // Frame counter for Parallax Animation
    reg [9:0] counter;
    always @(posedge vsync or negedge rst_n) begin
        if (~rst_n) begin
            counter <= 10'd0;
        end else begin
            counter <= counter + 1'b1;
        end
    end

    // Output pin setup
    assign uio_oe  = 8'h00; // All bidirectional IOs disabled
    assign uio_out = 8'h00;

    // ------------------------------------------------------------------------
    // 2. PARALLAX NIGHT SKY BACKGROUND
    // ------------------------------------------------------------------------
    wire [9:0] layer_a_coord = pix_y + (counter * 2);
    wire [9:0] layer_b_coord = pix_y + counter;
    wire [9:0] layer_c_coord = pix_y + (counter >> 1);
    wire [9:0] static_coord  = pix_x;

    wire layer_a_mask = (layer_a_coord[7] ^ static_coord[7]) & (pix_y[0] ^ pix_x[0]); 
    wire layer_b_mask = (layer_b_coord[6] ^ static_coord[6]) & (~pix_y[0] ^ pix_x[1]); 
    wire layer_c_mask = layer_c_coord[6] ^ static_coord[6];                          

    // Night Palette Colors
    localparam [5:0] COLOR_LAYER_A = 6'b00_01_10; // Soft Slate-Blue
    localparam [5:0] COLOR_LAYER_B = 6'b00_00_10; // Medium Night Blue
    localparam [5:0] COLOR_LAYER_C = 6'b00_00_01; // Soft Midnight Blue
    localparam [5:0] COLOR_BG      = 6'b00_00_01; // Deepest Midnight

    reg [1:0] active_sky_R, active_sky_G, active_sky_B;

    always @(*) begin
        if (layer_a_mask) begin
            {active_sky_R, active_sky_G, active_sky_B} = COLOR_LAYER_A;
        end else if (layer_b_mask) begin
            {active_sky_R, active_sky_G, active_sky_B} = COLOR_LAYER_B;
        end else if (layer_c_mask) begin
            {active_sky_R, active_sky_G, active_sky_B} = COLOR_LAYER_C;
        end else begin
            {active_sky_R, active_sky_G, active_sky_B} = COLOR_BG; 
        end
    end

    // ------------------------------------------------------------------------
    // 3. PRIORITY ENCODER FOR MOON PHASES
    // ------------------------------------------------------------------------
    reg [2:0] moon_phase;
    always @(*) begin
        if (ui_in[7])      moon_phase = 3'd7; 
        else if (ui_in[6]) moon_phase = 3'd3; 
        else if (ui_in[5]) moon_phase = 3'd6; 
        else if (ui_in[4]) moon_phase = 3'd4; 
        else if (ui_in[3]) moon_phase = 3'd2; 
        else if (ui_in[2]) moon_phase = 3'd5; 
        else if (ui_in[1]) moon_phase = 3'd1; 
        else               moon_phase = 3'd1; 
    end

    // ------------------------------------------------------------------------
    // 4. ENTITY MANAGER (16 REGISTER-BASED STARS)
    // ------------------------------------------------------------------------
    reg [15:0] lfsr;
    wire feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    // Explicit registers for up to 16 active stars
    reg [9:0] star_pos   [0:15]; // Grid Cell Position: Y[9:5], X[4:0]
    reg [3:0] star_life  [0:15]; // Star lifetime counter
    reg [1:0] star_color [0:15]; // Color palette index
    reg       star_shape [0:15]; // Shape: 1 = asterisk, 0 = circle

    reg [3:0] head_ptr;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            lfsr     <= 16'hACE1;
            head_ptr <= 4'd0;
            
            // Clean reset to prevent OpenLane $wrmux inference loop
            for (i = 0; i < 16; i = i + 1) begin
                star_pos[i]   <= 10'd0;
                star_life[i]  <= 4'd0;
                star_color[i] <= 2'd0;
                star_shape[i] <= 1'b0;
            end
        end else begin
            lfsr <= {lfsr[14:0], feedback};

            // Spawn and decrement stars once per frame at top-left pixel
            if (pix_x == 10'd0 && pix_y == 10'd0) begin
                // Spawn a new star periodically
                if (lfsr[15:13] == 3'b101) begin
                    star_pos[head_ptr]   <= lfsr[9:0];
                    star_life[head_ptr]  <= 4'd10;
                    star_color[head_ptr] <= lfsr[2:1];
                    star_shape[head_ptr] <= lfsr[0];
                    head_ptr             <= head_ptr + 1'b1;
                end

                // Decrement life of active stars
                for (i = 0; i < 16; i = i + 1) begin
                    if (star_life[i] > 4'd0) begin
                        star_life[i] <= star_life[i] - 1'b1;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 5. MOON RENDERER
    // ------------------------------------------------------------------------
    localparam CENTER_X = 320;
    localparam CENTER_Y = 240;

    wire signed [10:0] dx = pix_x - CENTER_X;
    wire signed [10:0] dy = pix_y - CENTER_Y;
    wire [20:0] dist_sq   = (dx * dx) + (dy * dy);

    localparam MOON_RADIUS_SQ = 90 * 90;
    wire is_in_moon_circle = (dist_sq <= MOON_RADIUS_SQ);

    wire signed [10:0] dx_offset_crescent_wax = dx - 38;
    wire signed [10:0] dx_offset_crescent_wan = dx + 38;

    wire is_in_crescent_wax_cutout = (((dx_offset_crescent_wax * dx_offset_crescent_wax) + (dy * dy)) <= MOON_RADIUS_SQ);
    wire is_in_crescent_wan_cutout = (((dx_offset_crescent_wan * dx_offset_crescent_wan) + (dy * dy)) <= MOON_RADIUS_SQ);

    reg is_lit_moon;
    always @(*) begin
        case (moon_phase)
            3'd0: is_lit_moon = 1'b0; // New Moon
            3'd1: is_lit_moon = is_in_moon_circle && !is_in_crescent_wax_cutout;
            3'd2: is_lit_moon = is_in_moon_circle && is_in_crescent_wan_cutout;
            3'd3: is_lit_moon = is_in_moon_circle && (dx > 0);
            3'd4: is_lit_moon = is_in_moon_circle; // Full Moon
            3'd5: is_lit_moon = is_in_moon_circle && (dx < 0);
            3'd6: is_lit_moon = is_in_moon_circle && is_in_crescent_wax_cutout;
            3'd7: is_lit_moon = is_in_moon_circle && !is_in_crescent_wan_cutout;
            default: is_lit_moon = 1'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // 6. NIGHT STAR FIELD RENDERER
    // ------------------------------------------------------------------------
    wire [4:0] grid_x = pix_x[9:5];
    wire [4:0] grid_y = pix_y[9:5];
    wire [9:0] current_cell = {grid_y, grid_x};

    wire [2:0] local_x = pix_x[4:2];
    wire [2:0] local_y = pix_y[4:2];

    wire is_asterisk_pixel = ((local_x == 3) && (local_y >= 2 && local_y <= 4)) || 
                             ((local_y == 3) && (local_x >= 2 && local_x <= 4));

    wire signed [3:0] dot_dx = local_x - 3;
    wire signed [3:0] dot_dy = local_y - 3;
    wire is_circle_pixel = ((dot_dx * dot_dx) + (dot_dy * dot_dy) <= 2);

    // Parallel search across all 16 star slots
    reg is_star_active;
    reg [1:0] star_color_code;
    
    integer k;
    always @(*) begin
        is_star_active  = 1'b0;
        star_color_code = 2'b00;
        for (k = 0; k < 16; k = k + 1) begin
            if ((star_life[k] > 0) && (star_pos[k] == current_cell)) begin
                if (star_shape[k] ? is_asterisk_pixel : is_circle_pixel) begin
                    is_star_active  = ~is_lit_moon;
                    star_color_code = star_color[k];
                end
            end
        end
    end

    reg [5:0] final_star_rgb;
    always @(*) begin
        case (star_color_code)
            2'b00: final_star_rgb = 6'b01_11_10; // #57f2a4 (Mint Green)
            2'b01: final_star_rgb = 6'b11_10_10; // #f58c9a (Soft Pink)
            2'b10: final_star_rgb = 6'b10_11_11; // #94daff (Sky Blue)
            2'b11: final_star_rgb = 6'b11_11_11; // Pure White
        endcase
    end

    // ------------------------------------------------------------------------
    // 7. COLOR COMPOSITOR
    // ------------------------------------------------------------------------
    reg [1:0] R, G, B;

    always @(*) begin
        if (!video_active) begin
            {R, G, B} = 6'b00_00_00; // Blanking
        end else if (is_lit_moon) begin
            {R, G, B} = 6'b11_11_00; // Bright Yellow Moon
        end else if (is_star_active) begin
            {R, G, B} = final_star_rgb; // Custom Color Stars
        end else begin
            {R, G, B} = {active_sky_R, active_sky_G, active_sky_B}; // Night Parallax Background
        end
    end

    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

    wire _unused_ok = &{ena, uio_in, ui_in[0]};

endmodule
