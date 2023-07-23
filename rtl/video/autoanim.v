// NeoGeo logic definition
// Copyright (C) 2018 Sean Gonsalves
// Rewrite to fully synchronous logic by (C) 2023 Gyorgy Szombathelyi
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/* verilator lint_off PINMISSING */

module autoanim_sync(
	input CLK,
	input RASTER8,
	input RESETP,
	input [7:0] AA_SPEED,
	output [2:0] AA_COUNT
);

	wire [3:0] D151_Q;

	//wire B91_CO;
	//wire E117_CO;

	//wire E95A_OUT = ~|{E117_CO, 1'b0};	// Used for test mode
	//wire E149_OUT = ~^{CLK, 1'b0};			// Used for test mode
	
	// Timer counters
	//C43 B91(E149_OUT, ~AA_SPEED[3:0], E95A_OUT, 1'b1, 1'b1, 1'b1, , B91_CO);
	//C43 E117(E149_OUT, ~AA_SPEED[7:4], E95A_OUT, 1'b1, B91_CO, 1'b1, , E117_CO);

	// Auto-anim tile counter
	//C43 D151(E149_OUT, 4'b0000, 1'b1, 1'b1, E117_CO, RESETP, D151_Q);
	
	//assign AA_COUNT = D151_Q[2:0];

	reg [7:0] TIMER_CNT;
	reg [3:0] AA_CNT_FULL;
	always @(posedge CLK) begin
		reg RASTER8_d;
		RASTER8_d <= RASTER8;
		if (~RASTER8_d & RASTER8) begin
			if (&TIMER_CNT)
				TIMER_CNT <= ~AA_SPEED;
			else
				TIMER_CNT <= TIMER_CNT + 1'd1;

			if (!RESETP)
				AA_CNT_FULL <= 0;
			else if (&TIMER_CNT)
				AA_CNT_FULL <= AA_CNT_FULL + 1'd1;
		end
	end

	assign AA_COUNT = AA_CNT_FULL[2:0];

endmodule
