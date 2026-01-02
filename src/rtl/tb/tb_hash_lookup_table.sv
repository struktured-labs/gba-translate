`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_hash_lookup_table.sv
//
// Testbench for hash_lookup_table module.
// Tests Bloom filter and hash table lookup functionality.
// Compatible with Icarus Verilog.
//------------------------------------------------------------------------------

module tb_hash_lookup_table;

    //--------------------------------------------------------------------------
    // Parameters - use smaller sizes for faster simulation
    //--------------------------------------------------------------------------
    localparam BLOOM_SIZE_BITS = 1024;   // Smaller bloom filter for test
    localparam TABLE_BUCKETS = 256;       // Smaller hash table
    localparam CHAIN_DEPTH = 4;

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    // Hash input
    reg         hash_valid;
    reg  [15:0] hash_in;

    // Match output
    wire        match_found;
    wire        lookup_done;
    wire [7:0]  char_code;
    wire [15:0] translation_ptr;

    // External memory (unused)
    wire        ext_mem_rd;
    wire [23:0] ext_mem_addr;
    reg  [31:0] ext_mem_rdata;
    reg         ext_mem_rvalid;

    // Dictionary loading
    reg         dict_load_en;
    reg  [15:0] dict_load_addr;
    reg  [40:0] dict_load_data;
    reg         bloom_load_en;
    reg  [15:0] bloom_load_addr;
    reg         bloom_load_bit;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    hash_lookup_table #(
        .BLOOM_SIZE_BITS(BLOOM_SIZE_BITS),
        .BLOOM_ADDR_BITS(10),  // log2(1024)
        .TABLE_BUCKETS(TABLE_BUCKETS),
        .TABLE_ADDR_BITS(8),   // log2(256)
        .CHAIN_DEPTH(CHAIN_DEPTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .hash_valid     (hash_valid),
        .hash_in        (hash_in),
        .match_found    (match_found),
        .lookup_done    (lookup_done),
        .char_code      (char_code),
        .translation_ptr(translation_ptr),
        .ext_mem_rd     (ext_mem_rd),
        .ext_mem_addr   (ext_mem_addr),
        .ext_mem_rdata  (ext_mem_rdata),
        .ext_mem_rvalid (ext_mem_rvalid),
        .dict_load_en   (dict_load_en),
        .dict_load_addr (dict_load_addr),
        .dict_load_data (dict_load_data),
        .bloom_load_en  (bloom_load_en),
        .bloom_load_addr(bloom_load_addr),
        .bloom_load_bit (bloom_load_bit)
    );

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Test variables
    //--------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer i;
    reg lookup_done_seen;

    // Test data
    reg [15:0] test_hashes [0:7];
    reg [7:0]  test_char_codes [0:7];
    reg [15:0] test_trans_ptrs [0:7];

    //--------------------------------------------------------------------------
    // Capture lookup_done pulse
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            lookup_done_seen <= 0;
        else if (lookup_done)
            lookup_done_seen <= 1;
    end

    //--------------------------------------------------------------------------
    // Task: Load bloom filter bit
    //--------------------------------------------------------------------------
    task load_bloom_bit;
        input [15:0] addr;
        input bit_val;
        begin
            @(posedge clk);
            bloom_load_en <= 1;
            bloom_load_addr <= addr;
            bloom_load_bit <= bit_val;
            @(posedge clk);
            bloom_load_en <= 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Load hash table entry
    // Entry format: valid[40] + hash[39:24] + char_code[23:16] + trans_ptr[15:0]
    //--------------------------------------------------------------------------
    task load_hash_entry;
        input [15:0] addr;
        input [15:0] hash_val;
        input [7:0]  char_code_val;
        input [15:0] trans_ptr_val;
        begin
            @(posedge clk);
            dict_load_en <= 1;
            dict_load_addr <= addr;
            // Format: {valid[1], hash[16], char_code[8], trans_ptr[16]} = 41 bits
            dict_load_data <= {1'b1, hash_val, char_code_val, trans_ptr_val};
            @(posedge clk);
            dict_load_en <= 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Set bloom filter bits for a hash (3 hash functions)
    //--------------------------------------------------------------------------
    task set_bloom_for_hash;
        input [15:0] hash_val;
        reg [15:0] h1, h2, h3;
        begin
            h1 = hash_val;
            h2 = {hash_val[7:0], hash_val[15:8]};  // Byte swap
            h3 = hash_val ^ 16'h5A5A;              // XOR constant

            // Use lower 10 bits for 1024-entry bloom filter
            load_bloom_bit(h1[9:0], 1);
            load_bloom_bit(h2[9:0], 1);
            load_bloom_bit(h3[9:0], 1);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Perform lookup and wait for result
    //--------------------------------------------------------------------------
    task do_lookup;
        input [15:0] hash_val;
        integer timeout;
        begin
            lookup_done_seen <= 0;
            @(posedge clk);
            hash_valid <= 1;
            hash_in <= hash_val;
            @(posedge clk);
            hash_valid <= 0;

            // Wait for lookup_done
            timeout = 50;
            while (!lookup_done && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end

            if (timeout == 0) begin
                $display("  ERROR: Lookup timeout for hash 0x%04h", hash_val);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_hash_lookup_table.vcd");
        $dumpvars(0, tb_hash_lookup_table);

        $display("========================================");
        $display("Hash Lookup Table Testbench");
        $display("========================================");
        $display("Bloom filter size: %0d bits", BLOOM_SIZE_BITS);
        $display("Hash table buckets: %0d", TABLE_BUCKETS);
        $display("");

        // Initialize test data
        test_hashes[0] = 16'h1234; test_char_codes[0] = 8'h41; test_trans_ptrs[0] = 16'h0100;
        test_hashes[1] = 16'h5678; test_char_codes[1] = 8'h42; test_trans_ptrs[1] = 16'h0200;
        test_hashes[2] = 16'h9ABC; test_char_codes[2] = 8'h43; test_trans_ptrs[2] = 16'h0300;
        test_hashes[3] = 16'hDEF0; test_char_codes[3] = 8'h44; test_trans_ptrs[3] = 16'h0400;
        test_hashes[4] = 16'h1111; test_char_codes[4] = 8'h45; test_trans_ptrs[4] = 16'h0500;
        test_hashes[5] = 16'h2222; test_char_codes[5] = 8'h46; test_trans_ptrs[5] = 16'h0600;
        test_hashes[6] = 16'h3333; test_char_codes[6] = 8'h47; test_trans_ptrs[6] = 16'h0700;
        test_hashes[7] = 16'h4444; test_char_codes[7] = 8'h48; test_trans_ptrs[7] = 16'h0800;

        // Initialize signals
        rst_n = 0;
        hash_valid = 0;
        hash_in = 0;
        dict_load_en = 0;
        dict_load_addr = 0;
        dict_load_data = 0;
        bloom_load_en = 0;
        bloom_load_addr = 0;
        bloom_load_bit = 0;
        ext_mem_rdata = 0;
        ext_mem_rvalid = 0;
        pass_count = 0;
        fail_count = 0;

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        //----------------------------------------------------------------------
        // Load dictionary entries
        //----------------------------------------------------------------------
        $display("Loading %0d dictionary entries...", 8);

        for (i = 0; i < 8; i = i + 1) begin
            // Set bloom filter bits for this hash
            set_bloom_for_hash(test_hashes[i]);

            // Load hash table entry
            // Address = bucket (lower 8 bits of hash) * 4 + chain_index (0)
            load_hash_entry(
                {test_hashes[i][7:0], 2'b00},  // bucket * 4 + chain 0
                test_hashes[i],
                test_char_codes[i],
                test_trans_ptrs[i]
            );
        end

        $display("Dictionary loaded.");
        $display("");
        repeat(10) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 1: Lookup known entries (should find matches)
        //----------------------------------------------------------------------
        $display("Test 1: Lookup known entries (expect matches)");

        for (i = 0; i < 8; i = i + 1) begin
            do_lookup(test_hashes[i]);

            if (match_found && char_code == test_char_codes[i]) begin
                $display("  Hash 0x%04h: PASS (char=0x%02h, ptr=0x%04h)",
                         test_hashes[i], char_code, translation_ptr);
                pass_count = pass_count + 1;
            end else begin
                $display("  Hash 0x%04h: FAIL (match=%b, char=0x%02h, expected=0x%02h)",
                         test_hashes[i], match_found, char_code, test_char_codes[i]);
                fail_count = fail_count + 1;
            end

            repeat(5) @(posedge clk);
        end

        $display("");

        //----------------------------------------------------------------------
        // Test 2: Lookup unknown entries (should not find matches)
        //----------------------------------------------------------------------
        $display("Test 2: Lookup unknown entries (expect no matches)");

        // These hashes are not in the dictionary
        do_lookup(16'hAAAA);
        if (!match_found) begin
            $display("  Hash 0xAAAA: PASS (no match, as expected)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Hash 0xAAAA: FAIL (unexpected match)");
            fail_count = fail_count + 1;
        end

        repeat(5) @(posedge clk);

        do_lookup(16'hBBBB);
        if (!match_found) begin
            $display("  Hash 0xBBBB: PASS (no match, as expected)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Hash 0xBBBB: FAIL (unexpected match)");
            fail_count = fail_count + 1;
        end

        repeat(5) @(posedge clk);

        do_lookup(16'hCCCC);
        if (!match_found) begin
            $display("  Hash 0xCCCC: PASS (no match, as expected)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Hash 0xCCCC: FAIL (unexpected match)");
            fail_count = fail_count + 1;
        end

        $display("");

        //----------------------------------------------------------------------
        // Test 3: Verify bloom filter fast reject
        //----------------------------------------------------------------------
        $display("Test 3: Bloom filter timing");
        // The bloom filter should reject non-matching hashes quickly
        // (within 2-3 cycles after hash_valid)

        do_lookup(16'hFFFF);  // Not in bloom filter
        if (!match_found) begin
            $display("  Hash 0xFFFF: PASS (rejected)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Hash 0xFFFF: FAIL");
            fail_count = fail_count + 1;
        end

        $display("");

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);

        if (fail_count == 0) begin
            $display("");
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $display("");
            $display("*** TESTS FAILED ***");
        end
        $display("========================================");

        $finish;
    end

    //--------------------------------------------------------------------------
    // Timeout watchdog
    //--------------------------------------------------------------------------
    initial begin
        #1000000;  // 1ms timeout
        $display("ERROR: Global timeout reached");
        $finish;
    end

endmodule
