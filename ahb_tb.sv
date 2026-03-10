`timescale 1ns/1ps

module ahb_self_checking_tb;

    // Parameters
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter MEM_DEPTH  = 1024;

    // Signals
    logic HCLK, HRESETn;
    logic HSEL, HREADY, HWRITE;
    logic [ADDR_WIDTH-1:0] HADDR;
    logic [1:0] HTRANS;
    logic [2:0] HSIZE;
    logic [DATA_WIDTH-1:0] HWDATA;
    logic [(DATA_WIDTH/8)-1:0] HWSTRB;
    logic [DATA_WIDTH-1:0] HRDATA;
    logic HREADYOUT, HRESP;

    // Reference Memory and Scoreboard
    logic [DATA_WIDTH-1:0] ref_mem [MEM_DEPTH];
    int error_count = 0;

    // DUT Instance
    ahb5_subordinate #(ADDR_WIDTH, DATA_WIDTH, MEM_DEPTH) dut (.*);

    // Single Subordinate System: Loop back HREADYOUT to HREADY
    assign HREADY = HREADYOUT;

    // Clock Generation
    initial begin HCLK = 0; forever #5 HCLK = ~HCLK; end

   
    struct packed {
        logic        valid;
        logic        write;
        logic [31:0] addr;
    } addr_latch, data_latch; 

    
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            
            for(int i=0; i<MEM_DEPTH; i++) ref_mem[i] <= '0;
            
            addr_latch <= '0;
            data_latch <= '0;
        end else if (HREADYOUT && HREADY) begin
            // 1. Shift the pipeline
            data_latch <= addr_latch;
            
            addr_latch.valid <= HSEL && HTRANS[1];
            addr_latch.write <= HWRITE;
            addr_latch.addr  <= HADDR;

            // 2. Check the transfer that is FINISHING its data phase now
            if (data_latch.valid) begin
                if (data_latch.write) begin
                    for(int i=0; i<DATA_WIDTH/8; i++) begin
                        if (HWSTRB[i]) 
                            ref_mem[data_latch.addr[11:2]][i*8 +: 8] <= HWDATA[i*8 +: 8];
                    end
                end else begin
                    // Read check
                    if (HRDATA !== ref_mem[data_latch.addr[11:2]]) begin
                        $display("[ERROR] Mismatch at Addr %h! Exp: %h Got: %h", 
                                  data_latch.addr, ref_mem[data_latch.addr[11:2]], HRDATA);
                        error_count++;
                    end else begin
                        $display("[PASS] Read Addr %h: %h", data_latch.addr, HRDATA);
                    end
                end
            end
        end
    end

 
    // DRIVER TASKS
   
    task ahb_write(input [ADDR_WIDTH-1:0] addr, input [DATA_WIDTH-1:0] data, input [3:0] strb);
        @(posedge HCLK);
        while (!HREADYOUT) @(posedge HCLK); 
        HSEL   = 1;
        HTRANS = 2'b10; // NONSEQ
        HADDR  = addr;
        HWRITE = 1;
        HSIZE  = 3'b010; // Word size
        HWSTRB = strb;
        
        @(posedge HCLK);
        while (!HREADYOUT) @(posedge HCLK);
        HWDATA = data;
        HTRANS = 2'b00; // IDLE
        HSEL   = 0;
    endtask

    task ahb_read(input [ADDR_WIDTH-1:0] addr);
        @(posedge HCLK);
        while (!HREADYOUT) @(posedge HCLK);
        HSEL   = 1;
        HTRANS = 2'b10;
        HADDR  = addr;
        HWRITE = 0;
        HSIZE  = 3'b010; // Word size
        
        @(posedge HCLK);
        while (!HREADYOUT) @(posedge HCLK);
        HTRANS = 2'b00;
        HSEL   = 0;
    endtask

    
    // TEST SEQUENCES
   
    initial begin
        // Reset
        HRESETn = 0; HSEL = 0; HTRANS = 0; HWRITE = 0; HSIZE = 0; HWSTRB = 0; HADDR = 0; HWDATA = 0;
        repeat(5) @(posedge HCLK);
        HRESETn = 1;

        $display("-------------------------------------------");
        $display("Starting AHB5 Self-Checking Test...");
        $display("-------------------------------------------");

        // Test 1: Simple Write/Read
        ahb_write(32'h0000_0100, 32'hDEADBEEF, 4'hF);
        ahb_read(32'h0000_0100);

        // Test 2: Byte Write (Strobe test)
        ahb_write(32'h0000_0200, 32'hAAAA_BBBB, 4'b0001); 
        ahb_read(32'h0000_0200);

        // Test 3: Standard sequence check
        ahb_write(32'h0000_0300, 32'h1111_1111, 4'hF);
        ahb_write(32'h0000_0304, 32'h2222_2222, 4'hF);
        ahb_read(32'h0000_0300);
        ahb_read(32'h0000_0304);

        repeat(5) @(posedge HCLK);
        
        $display("-------------------------------------------");
        if (error_count == 0) $display("FINAL RESULT: ALL TESTS PASSED!");
        else $display("FINAL RESULT: FAILED with %0d errors", error_count);
        $display("-------------------------------------------");
        $finish;
    end
endmodule