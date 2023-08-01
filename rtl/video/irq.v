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

module irq_sync(
	input CLK,
	input WR_ACK,
	input [2:0] ACK_BITS,
	input RESET_IRQ,
	input TIMER_IRQ,
	input TIMER_IRQ_EN,
	input VBL_IRQ,
	input VBL_IRQ_EN,
	input CLK_EN,
	output IPL0, IPL1
);

	wire [2:0] ACK;
	//wire [3:0] B32_Q;
	
	wire nWR_ACK = ~WR_ACK;

	assign ACK[0] = ~&{nWR_ACK, ACK_BITS[0]};
	assign ACK[1] = ~&{nWR_ACK, ACK_BITS[1]};
	assign ACK[2] = ~&{nWR_ACK, ACK_BITS[2]};
	
	wire B56_Q, B56_nQ = ~B56_Q, B52_Q, B52_nQ = ~B52_Q, C52_Q;
	//FD3 B56(RESET_IRQ, 1'b0, ACK[0], B56_Q, B56_nQ);
	//FD3 B52(TIMER_IRQ, 1'b0, ACK[1], B52_Q, B52_nQ);
	//FD3 C52(VBL_IRQ, 1'b0, ACK[2], C52_Q);
	register B56(CLK, ~ACK[0], 1'b0, RESET_IRQ, 1'b0, B56_Q);
	register B52(CLK, ~ACK[1], 1'b0, TIMER_IRQ, ~TIMER_IRQ_EN, B52_Q);
	register C52(CLK, ~ACK[2], 1'b0, VBL_IRQ, ~VBL_IRQ_EN, C52_Q);
	
	// B49
	wire B49_OUT = B52_Q | B56_nQ;
	
	// B50A
	wire B50A_OUT = ~|{C52_Q, B56_nQ, B52_nQ};
	
	//FDSCell B32(CLK, {1'b0, B50A_OUT, B49_OUT, B56_Q}, B32_Q);
	reg [3:0] B32_Q;
	always @(posedge CLK) if (CLK_EN) B32_Q <= {1'b0, B50A_OUT, B49_OUT, B56_Q};
	
	assign IPL0 = ~|{~B32_Q[0], B32_Q[2]};
	assign IPL1 = ~|{~B32_Q[1], ~B32_Q[0]};
	
	// Interrupt priority encoder
	// IRQ  IPL
	// xx1: 100 Reset IRQ
	// x10: 101 Timer IRQ
	// 100: 110 VBL IRQ
	// 000: 111 No interrupt

endmodule
