/*  This file is part of JT49.

    JT49 is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT49 is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT49.  If not, see <http://www.gnu.org/licenses/>.
    
    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 10-Nov-2018
    
    Based on sqmusic, by the same author
    
    */

`timescale 1ns / 1ps
module jt49_exp(
    input      [4:0] din,
    output reg [7:0] dout 
);

always @(din)
    case (din) // each step is 1/sqrt(2) of the previous value, starting from the end
        5'h00: dout=8'd0;
        5'h01: dout=8'd1;
        5'h02: dout=8'd2;
        5'h03: dout=8'd2;
        5'h04: dout=8'd2;
        5'h05: dout=8'd3;
        5'h06: dout=8'd3;
        5'h07: dout=8'd4;
        5'h08: dout=8'd5;
        5'h09: dout=8'd6;
        5'h0A: dout=8'd7;
        5'h0B: dout=8'd8;
        5'h0C: dout=8'd9;
        5'h0D: dout=8'd11;
        5'h0E: dout=8'd13;
        5'h0F: dout=8'd16; 
        5'h10: dout=8'd19;
        5'h11: dout=8'd23;
        5'h12: dout=8'd27;
        5'h13: dout=8'd32;
        5'h14: dout=8'd38;
        5'h15: dout=8'd45;
        5'h16: dout=8'd54;
        5'h17: dout=8'd64;
        5'h18: dout=8'd76;
        5'h19: dout=8'd90;
        5'h1A: dout=8'd107;
        5'h1B: dout=8'd128;
        5'h1C: dout=8'd152;
        5'h1D: dout=8'd180;
        5'h1E: dout=8'd214;
        5'h1F: dout=8'd255; 
    endcase    
endmodule
