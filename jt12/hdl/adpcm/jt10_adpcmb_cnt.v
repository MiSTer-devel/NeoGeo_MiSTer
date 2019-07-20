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
*/

// ADPCM-B counter

module jt10_adpcmb_cnt(
    input               rst_n,
    input               clk,    // CPU clock
    input               cen,    // clk & cen = 55 kHz

    // counter control
    input   [15:0]      delta_n,
    input               clr,
    input               on,
    // Address
    input       [15:0]  astart,
    input       [15:0]  aend,
    input               arepeat,
    output  reg [23:0]  addr,
    output  reg         nibble_sel,
    // Flag
    output  reg         flag,
    input               clr_flag,

    output  reg         adv
);

// Counter
reg [15:0] cnt;

always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
        cnt <= 'd0;
        adv <= 'b0;
    end else if(cen) begin
        if( clr ) begin
            cnt <= 'd0;
            adv <= 'b0;
        end else begin
            if( on ) 
                {adv, cnt} <= {1'b0, cnt} + {1'b0, delta_n };
            else
                adv <= 1'b1; // let the rest of the signal chain advance
                    // when channel is off so all registers go to reset values
        end
    end

reg set_flag, last_set;

always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
        flag     <= 1'b0;
        last_set <= 'b0;
    end else begin
        last_set <= set_flag;
        if( clr_flag ) flag <= 1'b0;
        if( !last_set && set_flag ) flag <= 1'b1;
    end

// Address
reg last_on;

always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
        addr       <= 'd0;
        nibble_sel <= 'b0;
        set_flag   <= 'd0;
    end else if(cen) begin
        last_on <= on;

        if( (on && !last_on) || clr ) begin
            addr <= {astart,8'd0};
            nibble_sel <= 'b0;
        end else if( on && adv ) begin
            if( addr[23:8] < aend ) begin
                { addr, nibble_sel } <= { addr, nibble_sel } + 25'd1;
                set_flag <= 'd0;
            end
            else begin
                set_flag <= 'd1;
                if(arepeat) begin
                    addr <= {astart,8'd0};
                    nibble_sel <= 'b0;
                end
            end
        end
    end // cen


endmodule // jt10_adpcmb_cnt