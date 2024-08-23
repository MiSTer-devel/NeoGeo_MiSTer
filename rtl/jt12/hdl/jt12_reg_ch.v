/*  This file is part of JT12.

    JT12 is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT12 is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT12.  If not, see <http://www.gnu.org/licenses/>.
    
    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 23-10-2019
    */

// Channel data is not stored in a CSR as operators
// Proof of that is the Splatter House arcade writes
// channel and operator data in two consequitive accesses
// without enough time in between to have the eight
// channels go through the CSR. So the channel data
// cannot be CSR, but regular registers.
module jt12_reg_ch(
    input         rst,
    input         clk,
    input         cen,
    input  [ 7:0] din,

    input  [ 2:0] up_ch,
    input  [ 5:0] latch_fnum,
    input         up_fnumlo,
    input         up_alg,
    input         up_pms,

    input      [ 2:0] ch, // next active channel
    output reg [ 2:0] block,
    output reg [10:0] fnum,
    output reg [ 2:0] fb,
    output reg [ 2:0] alg,
    output reg [ 1:0] rl,
    output reg [ 1:0] ams_IV,
    output reg [ 2:0] pms
);

parameter NUM_CH=6;
localparam M=NUM_CH==3?2:3;

reg [ 2:0] reg_block[0:NUM_CH-1];
reg [10:0] reg_fnum [0:NUM_CH-1];
reg [ 2:0] reg_fb   [0:NUM_CH-1];
reg [ 2:0] reg_alg  [0:NUM_CH-1];
reg [ 1:0] reg_rl   [0:NUM_CH-1];
reg [ 1:0] reg_ams  [0:NUM_CH-1];
reg [ 2:0] reg_pms  [0:NUM_CH-1];
reg [ 2:0] ch_IV;

wire [M-1:0] ch_sel, out_sel;

function [M-1:0] chtr( input [2:0] chin );
reg [2:0] aux;
begin
    aux  = chin[M-1] ? {1'b0,chin[1:0]}+3'd3 : // upper channels
                       {1'b0,chin[1:0]};       // lower
    chtr = NUM_CH==3 ? chin[M-1:0] : aux[M-1:0];

end
endfunction

assign ch_sel  = chtr(up_ch);
assign out_sel = chtr(ch);

integer i;
/* verilator lint_off WIDTHEXPAND */
always @* begin
    ch_IV = ch;
    if( NUM_CH==6 )
        case(out_sel)
            0: ch_IV = 3;
            1: ch_IV = 4;
            2: ch_IV = 5;
            3: ch_IV = 0;
            4: ch_IV = 1;
            5: ch_IV = 2;
            default: ch_IV = 0;
        endcase
end
/* verilator lint_on WIDTHEXPAND */

always @(posedge clk) if(cen) begin
    block <= reg_block[out_sel];
    fnum  <= reg_fnum [out_sel];
    fb    <= reg_fb   [out_sel];
    alg   <= reg_alg  [out_sel];
    rl    <= reg_rl   [out_sel];
    ams_IV<= reg_ams  [ch_IV[M-1:0]];
    pms   <= reg_pms  [out_sel];
    if( NUM_CH==3 ) rl <= 3; // YM2203 has no stereo output
end

always @(posedge clk, posedge rst) begin
    if( rst ) for(i=0;i<NUM_CH;i=i+1) begin
        reg_block[i] <= 0;
        reg_fnum [i] <= 0;
        reg_fb   [i] <= 0;
        reg_alg  [i] <= 0;
        reg_rl   [i] <= 3;
        reg_ams  [i] <= 0;
        reg_pms  [i] <= 0;
    end else begin
        i = 0; // prevents latch warning in Quartus
        if( up_fnumlo  ) { reg_block[ch_sel], reg_fnum[ch_sel] } <= {latch_fnum,din};
        if( up_alg ) begin
            reg_fb [ch_sel] <= din[5:3];
            reg_alg[ch_sel] <= din[2:0];
        end
        if( up_pms ) begin
            reg_rl [ch_sel] <= din[7:6];
            reg_ams[ch_sel] <= din[5:4];
            reg_pms[ch_sel] <= din[2:0];
        end
    end
end

endmodule