/*
 * Tiny Tapeout VGA: Night Phase Only Graphics Generator (Silent)
 * - Night Phase: Interactive moon phases, vertical parallax sky, and twinkling colored stars
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_vga_example (
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
    // 4. ENTITY MANAGER (NIGHT STARS GENERATOR)
    // ------------------------------------------------------------------------
    reg [15:0] lfsr;
    wire feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    // Grid: 32x24 cells
    reg [6:0] star_timer [0:1023];
    reg [9:0] active_stars [0:19];  
    reg [4:0] active_count;          
    reg [4:0] head_ptr;              
    reg [9:0] update_idx;

    wire [9:0] candidate_cell = lfsr[9:0];
    wire [4:0] cand_x = candidate_cell[4:0];
    wire [4:0] cand_y = candidate_cell[9:5];

    wire [9:0] cell_left  = {cand_y, cand_x - 5'd1};
    wire [9:0] cell_right = {cand_y, cand_x + 5'd1};
    wire [9:0] cell_up    = {cand_y - 5'd1, cand_x};
    wire [9:0] cell_down  = {cand_y + 5'd1, cand_x};

    wire is_candidate_clear = (star_timer[candidate_cell][6:3] == 0) &&
                              (star_timer[cell_left][6:3] == 0) &&
                              (star_timer[cell_right][6:3] == 0) &&
                              (star_timer[cell_up][6:3] == 0) &&
                              (star_timer[cell_down][6:3] == 0);

    always @(posedge clk) begin
        if (~rst_n) begin
            lfsr <= 16'hACE1;
            update_idx <= 0;
            active_count <= 0;
            head_ptr <= 0;
        end else begin
            lfsr <= {lfsr[14:0], feedback};

            if (pix_x == 0 && pix_y == 0) begin
                if ((lfsr[15:13] == 3'b101) && is_candidate_clear) begin
                    if (active_count == 5'd20) begin
                        star_timer[active_stars[head_ptr]] <= 7'd0;
                        star_timer[candidate_cell] <= {4'd10, lfsr[2:1], lfsr[0]};
                        active_stars[head_ptr] <= candidate_cell;
                        head_ptr <= (head_ptr == 5'd19) ? 5'd0 : head_ptr + 1'b1;
                    end else begin
                        star_timer[candidate_cell] <= {4'd10, lfsr[2:1], lfsr[0]};
                        active_stars[active_count] <= candidate_cell;
                        active_count <= active_count + 1'b1;
                    end
                end

                if (star_timer[update_idx][6:3] > 0) begin
                    star_timer[update_idx][6:3] <= star_timer[update_idx][6:3] - 1'b1;
                    if (star_timer[update_idx][6:3] == 4'd1 && active_count > 0) begin
                        active_count <= active_count - 1'b1;
                    end
                end
                
                update_idx <= update_idx + 1'b1;
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
    
    wire [6:0] star_entry = star_timer[current_cell];
    wire [3:0] star_life  = star_entry[6:3];
    wire [1:0] star_color_code = star_entry[2:1]; 
    wire       star_shape = star_entry[0]; 

    wire [2:0] local_x = pix_x[4:2];
    wire [2:0] local_y = pix_y[4:2];

    wire is_asterisk_pixel = ((local_x == 3) && (local_y >= 2 && local_y <= 4)) || 
                             ((local_y == 3) && (local_x >= 2 && local_x <= 4));

    wire signed [3:0] dot_dx = local_x - 3;
    wire signed [3:0] dot_dy = local_y - 3;
    wire is_circle_pixel = ((dot_dx * dot_dx) + (dot_dy * dot_dy) <= 2);

    wire is_shape_pixel = star_shape ? is_asterisk_pixel : is_circle_pixel;
    wire is_star_active = (star_life > 0) && is_shape_pixel && !is_lit_moon;

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