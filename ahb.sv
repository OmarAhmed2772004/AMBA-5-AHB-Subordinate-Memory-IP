`timescale 1ns/1ps

module ahb5_subordinate #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_DEPTH  = 1024
)(
    input  logic HCLK,
    input  logic HRESETn,

    input  logic HSEL,
    input  logic HREADY, // Global HREADY
    input  logic [ADDR_WIDTH-1:0] HADDR,
    input  logic [1:0] HTRANS,
    input  logic HWRITE,
    input  logic [2:0] HSIZE,
    input  logic [DATA_WIDTH-1:0] HWDATA,
    input  logic [(DATA_WIDTH/8)-1:0] HWSTRB,

    output logic [DATA_WIDTH-1:0] HRDATA,
    output logic HREADYOUT,
    output logic HRESP
);

    // Memory Array
    logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // State Machine for Two-Cycle Error Response
    typedef enum logic {ST_IDLE, ST_ERROR_2} state_t;
    state_t state;

    // Data Phase Latch
    struct packed {
        logic        valid;
        logic        write;
        logic [ADDR_WIDTH-1:0] addr;
        logic [2:0]  size;
    } data_phase;

    // Helper: Alignment Check
    function automatic logic is_aligned(logic [ADDR_WIDTH-1:0] a, logic [2:0] s);
        case(s)
            3'b001:  return (a[0] == 1'b0);    // Halfword (16-bit)
            3'b010:  return (a[1:0] == 2'b00); // Word (32-bit)
            default: return 1'b1;              // Byte or others
        endcase
    endfunction

    // Transfer is valid if Selected, Manager is Ready, and HTRANS is NONSEQ/SEQ
    wire valid_transfer = HSEL && HREADY && HTRANS[1];

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            // FIX: Initialize memory inside reset to avoid multiple driver errors
            for(int i=0; i<MEM_DEPTH; i++) mem[i] <= '0;
            
            data_phase <= '0;
            state      <= ST_IDLE;
            HREADYOUT  <= 1'b1;
            HRESP      <= 1'b0;
            HRDATA     <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // 1. Data Phase Execution (of the PREVIOUS address phase)
                    if (data_phase.valid && HREADY) begin
                        if (data_phase.write) begin
                            for (int i=0; i<DATA_WIDTH/8; i++) begin
                                if (HWSTRB[i])
                                    mem[data_phase.addr[11:2]][(i*8)+:8] <= HWDATA[(i*8)+:8];
                            end
                        end else begin
                            HRDATA <= mem[data_phase.addr[11:2]];
                        end
                    end

                    // 2. Address Phase Sampling
                    if (valid_transfer) begin
                        // Check for Alignment Error
                        if (!is_aligned(HADDR, HSIZE)) begin
                            // Start Cycle 1 of Error: HRESP=1, HREADYOUT=0
                            HRESP     <= 1'b1;
                            HREADYOUT <= 1'b0;
                            state     <= ST_ERROR_2;
                            data_phase.valid <= 1'b0;
                        end else begin
                            // Normal Transfer
                            data_phase.valid <= 1'b1;
                            data_phase.write <= HWRITE;
                            data_phase.addr  <= HADDR;
                            data_phase.size  <= HSIZE;
                            HRESP            <= 1'b0;
                            HREADYOUT        <= 1'b1;
                        end
                    end else if (HREADY) begin
                        // No new transfer requested
                        data_phase.valid <= 1'b0;
                        HRESP            <= 1'b0;
                        HREADYOUT        <= 1'b1;
                    end
                end

                ST_ERROR_2: begin
                    // Cycle 2 of Error: HRESP=1, HREADYOUT=1
                    HRESP     <= 1'b1;
                    HREADYOUT <= 1'b1;
                    state     <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule