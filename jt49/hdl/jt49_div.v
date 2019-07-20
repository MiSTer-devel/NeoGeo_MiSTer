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


module jt49_div #(parameter width=12 )(   
    input           clk, // this is the divided down clock from the core
    input           cen,
    input           rst_n,
    input [width-1:0]  period,
    output reg      div
);

reg [width-1:0]count;

wire [width-1:0] one = { {width-1{1'b0}}, 1'b1};

always @(posedge clk ) begin
  if( !rst_n) begin
    count <= one;
    div   <= 1'b0;
  end
  else if(cen) begin
    if( count == period ) begin
        count <= one;
        div   <= ~div;
    end
    else
        if( period!={width{1'b0}} ) count <=  count + one ;
  end
end

endmodule
