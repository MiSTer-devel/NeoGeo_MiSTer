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

module jt49 ( // note that input ports are not multiplexed
    input            rst_n,
    input            clk,    // signal on positive edge
    input            clk_en /* synthesis direct_enable = 1 */,
    input  [3:0]     addr,
    input            cs_n,
    input            wr_n,  // write
    input  [7:0]     din,
    input            sel, // if sel is low, the clock is divided by 2
    output reg [7:0] dout,
    output reg [9:0] sound,  // combined channel output
    output reg [7:0] A,      // linearised channel output
    output reg [7:0] B,
    output reg [7:0] C,

    input      [7:0] IOA_in,
    output     [7:0] IOA_out,

    input      [7:0] IOB_in,
    output     [7:0] IOB_out
);

parameter [1:0] COMP=2'b00;
parameter       CLKDIV=3;
wire [1:0] comp = COMP;

reg [7:0] regarray[15:0];

assign IOA_out = regarray[14];
assign IOB_out = regarray[15];

wire [4:0] envelope;
wire bitA, bitB, bitC;
wire noise;
reg Amix, Bmix, Cmix;

wire cen16, cen256;

jt49_cen #(.CLKDIV(CLKDIV)) u_cen(
    .clk    ( clk     ), 
    .rst_n  ( rst_n   ), 
    .cen    ( clk_en  ),
    .sel    ( sel     ),
    .cen16  ( cen16   ),
    .cen256 ( cen256  )
);

// internal modules operate at clk/16
jt49_div #(12) u_chA( 
    .clk        ( clk           ), 
    .rst_n      ( rst_n         ), 
    .cen        ( cen16         ),
    .period     ( {regarray[1][3:0], regarray[0][7:0] } ), 
    .div        ( bitA          )
);

jt49_div #(12) u_chB( 
    .clk        ( clk           ), 
    .rst_n      ( rst_n         ), 
    .cen        ( cen16         ),    
    .period     ( {regarray[3][3:0], regarray[2][7:0] } ),   
    .div        ( bitB          ) 
);

jt49_div #(12) u_chC( 
    .clk        ( clk           ), 
    .rst_n      ( rst_n         ), 
    .cen        ( cen16         ),
    .period     ( {regarray[5][3:0], regarray[4][7:0] } ), 
    .div        ( bitC          )
);

jt49_noise u_ng( 
    .clk    ( clk               ), 
    .cen    ( cen16             ),
    .rst_n  ( rst_n             ), 
    .period ( regarray[6][4:0]  ), 
    .noise  ( noise             ) 
);

// envelope generator
wire eg_step;
wire [15:0] eg_period   = {regarray[4'hc],regarray[4'hb]};
wire        null_period = eg_period == 16'h0;

jt49_div #(16) u_envdiv( 
    .clk    ( clk               ), 
    .cen    ( cen256            ),
    .rst_n  ( rst_n             ),
    .period ( eg_period         ), 
    .div    ( eg_step           ) 
);  

reg eg_restart;

jt49_eg u_env(
    .clk        ( clk               ),
    .cen        ( cen256            ),
    .step       ( eg_step           ),
    .rst_n      ( rst_n             ),
    .restart    ( eg_restart        ),
    .null_period( null_period       ),
    .ctrl       ( regarray[4'hD][3:0] ),
    .env        ( envelope          )
);

reg  [4:0] logA, logB, logC, log;
wire [7:0] lin;

jt49_exp u_exp(
    .clk    ( clk  ),
    .comp   ( comp ),
    .din    ( log  ),
    .dout   ( lin  )
);

wire [4:0] volA = { regarray[ 8][3:0], regarray[ 8][3] };
wire [4:0] volB = { regarray[ 9][3:0], regarray[ 9][3] };
wire [4:0] volC = { regarray[10][3:0], regarray[10][3] };
wire use_envA = regarray[ 8][4];
wire use_envB = regarray[ 9][4];
wire use_envC = regarray[10][4];

reg [3:0] acc_st;

always @(posedge clk) if( clk_en ) begin
    Amix <= (noise|regarray[7][3]) & (bitA|regarray[7][0]);
    Bmix <= (noise|regarray[7][4]) & (bitB|regarray[7][1]);
    Cmix <= (noise|regarray[7][5]) & (bitC|regarray[7][2]);

    logA <= !Amix ? 5'd0 : (use_envA ? envelope : volA );
    logB <= !Bmix ? 5'd0 : (use_envB ? envelope : volB );
    logC <= !Cmix ? 5'd0 : (use_envC ? envelope : volC );
end   

reg [9:0] acc;

always @(posedge clk, negedge rst_n) begin
    if( !rst_n ) begin
        acc_st <= 4'b1;
        acc    <= 10'd0;
    end else if(clk_en) begin
        acc_st <= { acc_st[2:0], acc_st[3] };
        acc <= acc + {2'b0,lin};
        case( acc_st )
            4'b0001: begin
                log   <= logA;
                acc   <= 10'd0;
                sound <= acc;
            end
            4'b0010: begin
                A   <= lin;
                log <= logB;
            end
            4'b0100: begin
                B   <= lin;
                log <= logC;
            end
            4'b1000: begin // last sum
                C   <= lin;
            end
        endcase
    end
end

reg [7:0] read_mask;

always @(*)
    case(addr)
        4'h0,4'h2,4'h4,4'h7,4'hb,4'hc,4'he,4'hf:
            read_mask = 8'hff;
        4'h1,4'h3,4'h5,4'hd:
            read_mask = 8'h0f;
        4'h6,4'h8,4'h9,4'ha: 
            read_mask = 8'h1f;
    endcase // addr

// register array
reg  last_wrn;
wire wrn_edge = ~(wr_n|cs_n) & last_wrn;
reg  eg_rst_rq;

always @(posedge clk, negedge rst_n)
    if( !rst_n ) begin
        dout      <= 8'd0;
        last_wrn  <= 1'b0;
        eg_rst_rq <= 1'b0;
        regarray[0]<=8'd0; regarray[4]<=8'd0; regarray[ 8]<=8'd0; regarray[12]<=8'd0;
        regarray[1]<=8'd0; regarray[5]<=8'd0; regarray[ 9]<=8'd0; regarray[13]<=8'd0;
        regarray[2]<=8'd0; regarray[6]<=8'd0; regarray[10]<=8'd0; regarray[14]<=8'd0;
        regarray[3]<=8'd0; regarray[7]<=8'd0; regarray[11]<=8'd0; regarray[15]<=8'd0;
    end else if( !cs_n ) begin
        dout <= regarray[ addr ] & read_mask;
        if( !wr_n ) begin
            regarray[addr] <= din;
            if(addr == 4'he && !regarray[7][6]) dout <= IOA_in;
            if(addr == 4'hf && !regarray[7][7]) dout <= IOB_in;
        end
        last_wrn  <= wr_n;
        if( eg_restart )
            eg_rst_rq <= 1'b0;
        else if ( addr == 4'hD && wrn_edge ) eg_rst_rq <= 1'b1;
    end

always @(posedge clk, negedge rst_n)
    if( !rst_n ) begin
        eg_restart <= 1'b0;
    end else if(cen256) begin
        eg_restart <= eg_rst_rq;
    end

endmodule
