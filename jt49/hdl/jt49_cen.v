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

module jt49_cen(
    input   clk,
    input   rst_n,
    input   cen,    // base clock enable signal
    input   sel,    // when low, divide by 2 once more
    output  reg cen8
);

reg [2:0] cencnt=3'd0;

always @(posedge clk) if(cen)
    cencnt <= cencnt+3'd1;

wire toggle = sel ? cencnt[1:0]==2'd0 : cencnt[2:0]==3'd0;

always @(negedge clk) begin
    cen8   <= cen && toggle;
end

endmodule // jt49_cen