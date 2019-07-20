/* This file is part of JT12.

 
    JT12 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT12 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT12.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 21-03-2019
    
    Each channel can use the full range of the DAC as they do not
    get summed in the real chip.

    Operator data is summed up without adding extra bits. This is
    the case of real YM3438, which was used on Megadrive 2 models.


*/

// YM2610
// ADPCM inputs
// Full OP resolution
// No PCM
// 4 OP channels

// ADPCM-A input is added for the time assigned to FM channel 0_10 (i.e. 3)

module jt10_acc(
    input               clk,
    input               clk_en /* synthesis direct_enable */,
    input signed [13:0] op_result,
    input        [ 1:0] rl,
    input               zero,
    input               s1_enters,
    input               s2_enters,
    input               s3_enters,
    input               s4_enters,
    input       [2:0]   cur_ch,
    input       [1:0]   cur_op,
    input   [2:0]       alg,
    input signed [15:0] adpcmA_l,
    input signed [15:0] adpcmA_r,
    input signed [15:0] adpcmB_l,
    input signed [15:0] adpcmB_r,
    // combined output
    output signed [15:0] left,
    output signed [15:0] right
);

reg sum_en;

always @(*) begin
    case ( alg )
        default: sum_en = s4_enters;
        3'd4: sum_en = s2_enters | s4_enters;
        3'd5,3'd6: sum_en = ~s1_enters;        
        3'd7: sum_en = 1'b1;
    endcase
end

wire left_en = rl[1];
wire right_en= rl[0];
wire signed [15:0] opext = { {2{op_result[13]}}, op_result };
reg  signed [15:0] acc_input_l, acc_input_r;
reg acc_en_l, acc_en_r;

// YM2610 mode:
// uses channels 2 and 6 for ADPCM data, throwing away FM data for those channels
always @(*)
    case( {cur_op,cur_ch} )
        {2'd0,3'd2}: begin // ADPCM-A:
            acc_input_l = adpcmA_l<<<4;
            acc_input_r = adpcmA_r<<<4;
            `ifndef NOMIX
            acc_en_l    = 1'b1;
            acc_en_r    = 1'b1;
            `else 
            acc_en_l    = 1'b0;
            acc_en_r    = 1'b0;
            `endif
        end
        {2'd0,3'd6}: begin // ADPCM-B:
            acc_input_l = adpcmB_l>>>2; // Operator width is 14 bit, ADPCM-B is 16 bit
            acc_input_r = adpcmB_r>>>2; // accumulator width per input channel is 14 bit
            `ifndef NOMIX
            acc_en_l    = 1'b1;
            acc_en_r    = 1'b1;
            `else 
            acc_en_l    = 1'b0;
            acc_en_r    = 1'b0;
            `endif
        end
        default: begin
            acc_input_l = opext;
            acc_input_r = opext;
            acc_en_l    = sum_en & left_en;
            acc_en_r    = sum_en & right_en;
        end
    endcase

// Continuous output

jt12_single_acc #(.win(16),.wout(16)) u_left(
    .clk        ( clk            ),
    .clk_en     ( clk_en         ),
    .op_result  ( acc_input_l    ),
    .sum_en     ( acc_en_l       ),
    .zero       ( zero           ),
    .snd        ( left           )
);

jt12_single_acc #(.win(16),.wout(16)) u_right(
    .clk        ( clk            ),
    .clk_en     ( clk_en         ),
    .op_result  ( acc_input_r    ),
    .sum_en     ( acc_en_r       ),
    .zero       ( zero           ),
    .snd        ( right          )
);

endmodule
