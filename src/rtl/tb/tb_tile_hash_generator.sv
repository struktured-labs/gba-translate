`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_tile_hash_generator.sv
//
// Testbench for tile_hash_generator module.
// Verifies CRC-16 computation matches Python reference implementation.
//------------------------------------------------------------------------------

module tb_tile_hash_generator;

    //--------------------------------------------------------------------------
    // Test vector include
    //--------------------------------------------------------------------------
    `include "test_vectors.svh"

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    logic        data_valid;
    logic [7:0]  data_in;
    logic        data_last;
    logic        hash_valid;
    logic [15:0] hash_out;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    tile_hash_generator dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_valid (data_valid),
        .data_in    (data_in),
        .data_last  (data_last),
        .hash_valid (hash_valid),
        .hash_out   (hash_out)
    );

    //--------------------------------------------------------------------------
    // Clock generation (100 MHz)
    //--------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Test variables
    //--------------------------------------------------------------------------
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [127:0] current_tile;
    reg [15:0] expected;
    reg [15:0] actual;

    //--------------------------------------------------------------------------
    // Task: Send one tile through the hash generator
    //--------------------------------------------------------------------------
    task send_tile;
        input [127:0] tile_data;
        integer i;
        begin
            // Send 16 bytes, MSB first (byte 0 is bits [127:120])
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                data_valid <= 1'b1;
                data_in <= tile_data[127 - i*8 -: 8];
                data_last <= (i == 15);
            end
            @(posedge clk);
            data_valid <= 1'b0;
            data_in <= 8'h00;
            data_last <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Wait for hash result
    //--------------------------------------------------------------------------
    task wait_for_hash;
        output [15:0] result;
        integer timeout;
        begin
            timeout = 100;
            while (!hash_valid && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("ERROR: Timeout waiting for hash_valid");
                result = 16'hDEAD;
            end else begin
                result = hash_out;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("Tile Hash Generator Testbench");
        $display("========================================");
        $display("Number of test vectors: %0d", NUM_TEST_VECTORS);
        $display("");

        // Initialize test vectors
        init_test_vectors();

        // Initialize signals
        rst_n = 0;
        data_valid = 0;
        data_in = 0;
        data_last = 0;
        pass_count = 0;
        fail_count = 0;

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        // Run all test vectors
        for (test_num = 0; test_num < NUM_TEST_VECTORS; test_num = test_num + 1) begin
            current_tile = TILE_DATA[test_num];
            expected = EXPECTED_HASH[test_num];

            $display("Test %0d: %s", test_num, get_test_name(test_num));
            $display("  Tile data: %032h", current_tile);
            $display("  Expected hash: 0x%04h", expected);

            // Send tile data
            send_tile(current_tile);

            // Wait for result
            wait_for_hash(actual);

            // Check result
            if (actual == expected) begin
                $display("  Result: 0x%04h - PASS", actual);
                pass_count = pass_count + 1;
            end else begin
                $display("  Result: 0x%04h - FAIL (expected 0x%04h)", actual, expected);
                fail_count = fail_count + 1;
            end
            $display("");

            // Small delay between tests
            repeat(5) @(posedge clk);
        end

        // Summary
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Passed: %0d / %0d", pass_count, NUM_TEST_VECTORS);
        $display("Failed: %0d / %0d", fail_count, NUM_TEST_VECTORS);

        if (fail_count == 0) begin
            $display("");
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("");
            $display("*** TESTS FAILED ***");
        end
        $display("========================================");

        // Exit with appropriate code
        $finish;
    end

    //--------------------------------------------------------------------------
    // Timeout watchdog
    //--------------------------------------------------------------------------
    initial begin
        #100000;  // 100us timeout
        $display("ERROR: Global timeout reached");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Optional: VCD dump for waveform viewing
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_tile_hash_generator.vcd");
        $dumpvars(0, tb_tile_hash_generator);
    end

endmodule
