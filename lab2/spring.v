//`timescale 1ns/1ns

module testbench();
	
  reg                 clk, reset;
  reg  signed [17:0]  k1, k2, k13, k23, km, km3, D1, D2; 
  reg  signed [17:0]  init_v1, init_v2;
  reg  signed [17:0]  init_x1, init_x2;
  reg          [3:0]  dt;
  wire signed [17:0]  x1, x2;
	
    //Initialize clocks and index
   initial begin
    clk = 1'b0;
    k1  = 18'sd65536;
    k13 = 18'sd0;
    k2  = 18'sd65536;
    k23 = 18'sd0;
    km  = 18'sd65536;
    km3 = 18'sd0;
    
    D1  = 18'sd655;
    D2  = 18'sd655;
    
    //symmetric
    //init_v1 =  18'sd0;
    //init_v2 =  18'sd0;
    //init_x1 = -18'sd32768;
    //init_x2 =  18'sd32768;
    
    //anti-symtric
    init_v1 =  18'sd0;
    init_v2 =  18'sd0;
    init_x1 =  18'sd0;
    init_x2 =  18'sd42598;
    
    //random
    //init_v1 = -18'sd32768;
    //init_v2 =  18'sd13107;
    //init_x1 = -18'sd16384;
    //init_x2 =  18'sd45875;
    
    dt = 4'd9;
	end
	
	//Toggle the clocks
	always begin
		#10
		clk  = !clk;
	end
	
	//Intialize and drive signals
	initial begin
		reset  = 1'b1;
		#10 
		reset  = 1'b0;
		#30
		reset  = 1'b1;
	end
	

	euler_ode_solver DUT(.k1(k1), .k13(k13), .k2(k2), .k23(k23), .km(km), .km3(km3), .D1(D1), .D2(D2), 
                   .init_v1(init_v1), .init_v2(init_v2),
                   .init_x1(init_x1), .init_x2(init_x2),
                   .clk(clk), .reset(reset),
                   .dt(dt),
                   .x1(x1), .x2(x2) );
	
endmodule

	
//////////////////////////////////////////////
//// wire the integrators
//// time step: dt = 2>>9
//// v1(n+1) = v1(n) + dt*v2(n)
//integrator int1(v1, v2, 0,9,AnalogClock,AnalogReset);
//	
//// v2(n+1) = v2(n) + dt*(-k/m*v1(n) - d/m*v2(n))
//signed_mult K_M(v1xK_M, v1, 18'h1_0000); //Mult by k/m
//signed_mult D_M(v2xD_M, v2, 18'h0_0800); //Mult by d/m
//integrator int2(v2, (-v1xK_M-v2xD_M), 0,9,AnalogClock,AnalogReset);
    
/////////////////////////////////////////////////
//// integrator /////////////////////////////////

module integrator(out,funct,InitialOut,dt,clk,reset);
	output [17:0] out; 		//the state variable V
	input signed [17:0] funct;      //the dV/dt function
	input [3:0] dt ;		      // in units of SHIFT-right
	input clk, reset;
	input signed [17:0] InitialOut;  //the initial state variable V
	
	wire signed	[17:0] out, v1new ;
	reg signed	[17:0] v1 ;
	
	always @ (posedge clk) 
	begin
		if (reset==0) //reset	
			v1 <= InitialOut ; // 
		else 
			v1 <= v1new ;	
	end
	assign v1new = v1 + (funct>>>dt) ;
	assign out = v1 ;
endmodule

//////////////////////////////////////////////////
//// signed mult of 2.16 format 2'comp////////////

module signed_mult (out, a, b);
	output 		[17:0]	out;
	input 	signed	[17:0] 	a;
	input 	signed	[17:0] 	b;
	
	wire	signed	[17:0]	out;
	wire 	signed	[35:0]	mult_out;

	assign mult_out = a * b;
	//assign out = mult_out[33:17];
	assign out = {mult_out[35], mult_out[32:16]};
endmodule
//////////////////////////////////////////////////


///////////////ODE solver/////////////////////////
module euler_ode_solver
(
  input  signed [17:0] k1, k13, k2, k23, km, km3, D1, D2, 
  input  signed [17:0] init_v1, init_v2,
  input  signed [17:0] init_x1, init_x2,
  input                clk, reset, 
  input          [3:0] dt,
  output signed [17:0] x1, x2 
);
  
  wire signed [17:0] v1, v2;

  wire signed [17:0] functv1, functv2;
  wire signed [17:0] leftwall, rightwall;

  wire signed [17:0] sp1_f, sp2_f, spm_f;
  wire signed [17:0] k1x1, k13x13, k2x2, k23x23, kmxd, km3xd3;
  wire signed [17:0] x12, x13, x22, x23, xd2, xd3;
  wire signed [17:0] x1left, x2right, temp;
  
  wire signed [17:0] v1d1, v2d2;

  assign leftwall  = -18'sd65535;            // left  wall = -1
  assign rightwall =  18'sd65536;            // right wall =  1
  assign x1left=x1-leftwall;
  //sp1_f = k_1 * (x1 + 1) +  k_1_3 * (x1 + 1)^3;
  signed_mult k1x1mul   (k1x1,   k1,          x1left);//x1-leftwall);
  signed_mult k1square  (x12,    x1left,      x1left);//x1-leftwall, x1-leftwall);
  signed_mult k1cube    (x13,    x12,         x1left);//x1-leftwall);
  signed_mult k13x13mul (k13x13, k13,         x13   );
  
  assign sp1_f = k1x1 + k13x13;

  assign x2right=rightwall-x2;
  //sp2_f = k_2 * (1 - x2) +  k_2_3 * (1 - x2)^3;  
  signed_mult k2x2mul   (k2x2,   k2,           x2right);//rightwall-x2);
  signed_mult k2square  (x22,    x2right,      x2right);//rightwall-x2, rightwall-x2);
  signed_mult k2cube    (x23,    x22,          x2right);//rightwall-x2);
  signed_mult k23x23mul (k23x23, k23,          x23    );
  
  assign sp2_f = k2x2 + k23x23;
  
  assign temp=x2-x1;
  //spm_f = k_m * (x2 - x1) + k_m_3 * (x2 - x1)^3;
  signed_mult kmxdmul   (kmxd,   km,           temp);//x2-x1       );
  signed_mult xdsquare  (xd2,    temp,         temp);//x2-x1,        x2-x1       );
  signed_mult xdcube    (xd3,    xd2,          temp);//x2-x1       );
  signed_mult km3xd3mul (km3xd3, km3,          xd3 );
  
  assign spm_f = kmxd + km3xd3;
  
  //damping
  signed_mult v1damping (v1d1,   v1,           D1);
  signed_mult v2damping (v2d2,   v2,           D2);

    //x1
  integrator x1int (.out(x1), .funct(v1),      .dt(dt), .clk(clk), .reset(reset), .InitialOut(init_x1));

    //v1
  assign functv1 = -sp1_f - v1d1 + spm_f;
  integrator v1int (.out(v1), .funct(functv1), .dt(dt), .clk(clk), .reset(reset), .InitialOut(init_v1));


    //x2
  integrator x2int (.out(x2), .funct(v2),      .dt(dt), .clk(clk), .reset(reset), .InitialOut(init_x2));
    //v2
  assign functv2 = sp2_f - v2d2 - spm_f;
  integrator v2int (.out(v2), .funct(functv2), .dt(dt), .clk(clk), .reset(reset), .InitialOut(init_v2));

endmodule


