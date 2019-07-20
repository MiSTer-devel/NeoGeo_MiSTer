module DAC_test(
	input CLK_24M,
	output [7:0] VGA_R,
	output [7:0] VGA_G,
	output [7:0] VGA_B
);	
	// VGA DAC tester
	reg [23:0] TEMP;
	reg [2:0] TEST_COLOR;
	
	always @(posedge CLK_24M)
	begin
		TEMP <= TEMP + 1'b1;
		if (TEMP >= 24'd12000000)
		begin
			TEMP <= 24'd0;
			TEST_COLOR <= TEST_COLOR + 1'b1;
		end
	end
	
	assign VGA_R = TEST_COLOR[0] ? 8'hFF : 8'h00;
	assign VGA_G = TEST_COLOR[1] ? 8'hFF : 8'h00;
	assign VGA_B = TEST_COLOR[2] ? 8'hFF : 8'h00;
endmodule
