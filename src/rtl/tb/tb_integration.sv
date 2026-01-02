`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_integration.sv
//
// End-to-end integration test: vram_snooper → tile_hash_generator → hash_lookup_table
// Verifies the complete pipeline from VRAM write to character lookup.
//------------------------------------------------------------------------------

module tb_integration;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam TILE_SIZE_BYTES = 16;
    localparam BLOOM_SIZE_BITS = 1024;
    localparam TABLE_BUCKETS = 256;

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    // VRAM write interface (to vram_snooper)
    reg         vram_we;
    reg  [12:0] vram_addr;
    reg  [7:0]  vram_wdata;

    // Snooper configuration
    reg         cfg_enable;
    reg  [8:0]  cfg_text_tile_start;
    reg  [8:0]  cfg_text_tile_end;

    // Snooper → Hash generator
    wire        hash_data_valid;
    wire [7:0]  hash_data;
    wire        hash_data_last;
    wire        tile_capture_done;
    wire [8:0]  tile_index;

    // Hash generator → Lookup table
    wire        hash_valid;
    wire [15:0] hash_out;

    // Lookup table outputs
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
    // DUT instantiation: vram_snooper
    //--------------------------------------------------------------------------
    vram_snooper #(
        .TILE_SIZE_BYTES(TILE_SIZE_BYTES),
        .VRAM_TILE_START(13'h0000),
        .VRAM_TILE_END(13'h17FF)
    ) u_vram_snooper (
        .clk                (clk),
        .rst_n              (rst_n),
        .vram_we            (vram_we),
        .vram_addr          (vram_addr),
        .vram_wdata         (vram_wdata),
        .tile_capture_done  (tile_capture_done),
        .tile_index         (tile_index),
        .tile_is_text_region(),
        .hash_data_valid    (hash_data_valid),
        .hash_data          (hash_data),
        .hash_data_last     (hash_data_last),
        .cfg_enable         (cfg_enable),
        .cfg_text_tile_start(cfg_text_tile_start),
        .cfg_text_tile_end  (cfg_text_tile_end)
    );

    //--------------------------------------------------------------------------
    // DUT instantiation: tile_hash_generator
    //--------------------------------------------------------------------------
    tile_hash_generator u_tile_hash (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_valid (hash_data_valid),
        .data_in    (hash_data),
        .data_last  (hash_data_last),
        .hash_valid (hash_valid),
        .hash_out   (hash_out)
    );

    //--------------------------------------------------------------------------
    // DUT instantiation: hash_lookup_table
    //--------------------------------------------------------------------------
    hash_lookup_table #(
        .BLOOM_SIZE_BITS(BLOOM_SIZE_BITS),
        .BLOOM_ADDR_BITS(10),
        .TABLE_BUCKETS(TABLE_BUCKETS),
        .TABLE_ADDR_BITS(8),
        .CHAIN_DEPTH(4)
    ) u_hash_lookup (
        .clk            (clk),
        .rst_n          (rst_n),
        .hash_valid     (hash_valid),
        .hash_in        (hash_out),
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

    // Test tile data (16 bytes)
    reg [7:0] test_tile [0:15];

    // Pre-computed hashes for test tiles (CRC-16-CCITT)
    // These must match what tile_hash_generator produces
    reg [15:0] expected_hash;

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
    // Task: Set bloom filter bits for a hash
    //--------------------------------------------------------------------------
    task set_bloom_for_hash;
        input [15:0] hash_val;
        reg [15:0] h1, h2, h3;
        begin
            h1 = hash_val;
            h2 = {hash_val[7:0], hash_val[15:8]};
            h3 = hash_val ^ 16'h5A5A;
            load_bloom_bit(h1[9:0], 1);
            load_bloom_bit(h2[9:0], 1);
            load_bloom_bit(h3[9:0], 1);
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Load hash table entry
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
            dict_load_data <= {1'b1, hash_val, char_code_val, trans_ptr_val};
            @(posedge clk);
            dict_load_en <= 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Write a complete tile to VRAM
    //--------------------------------------------------------------------------
    task write_tile_to_vram;
        input [8:0] tile_idx;
        integer j;
        reg [12:0] base_addr;
        begin
            base_addr = {tile_idx, 4'b0000};  // tile_idx * 16
            for (j = 0; j < 16; j = j + 1) begin
                @(posedge clk);
                vram_we <= 1;
                vram_addr <= base_addr + j[3:0];
                vram_wdata <= test_tile[j];
            end
            @(posedge clk);
            vram_we <= 0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Wait for lookup completion
    //--------------------------------------------------------------------------
    task wait_for_lookup;
        integer timeout;
        begin
            lookup_done_seen <= 0;
            timeout = 100;
            while (!lookup_done && timeout > 0) begin
                @(posedge clk);
                timeout = timeout - 1;
            end
            if (timeout == 0) begin
                $display("  ERROR: Lookup timeout");
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // CRC-16-CCITT reference calculation (matches RTL)
    //--------------------------------------------------------------------------
    function [15:0] crc16_byte;
        input [15:0] crc_in;
        input [7:0] data_byte;
        reg [15:0] crc;
        integer bit_idx;
        begin
            crc = crc_in;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                if ((crc[15] ^ data_byte[7-bit_idx]) == 1'b1)
                    crc = {crc[14:0], 1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0], 1'b0};
            end
            crc16_byte = crc;
        end
    endfunction

    function [15:0] compute_tile_hash;
        input integer dummy;  // Verilog function requires input
        reg [15:0] crc;
        integer j;
        begin
            crc = 16'hFFFF;
            for (j = 0; j < 16; j = j + 1) begin
                crc = crc16_byte(crc, test_tile[j]);
            end
            compute_tile_hash = crc;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_integration.vcd");
        $dumpvars(0, tb_integration);

        $display("========================================");
        $display("Integration Testbench");
        $display("VRAM Snooper -> Hash Generator -> Lookup Table");
        $display("========================================");
        $display("");

        // Initialize signals
        rst_n = 0;
        vram_we = 0;
        vram_addr = 0;
        vram_wdata = 0;
        cfg_enable = 0;
        cfg_text_tile_start = 0;
        cfg_text_tile_end = 9'd383;
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

        // Initialize test tile (simple pattern)
        for (i = 0; i < 16; i = i + 1) begin
            test_tile[i] = 8'hA0 + i[7:0];
        end

        // Compute expected hash for this tile
        expected_hash = compute_tile_hash(0);
        $display("Test tile hash: 0x%04h", expected_hash);

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        //----------------------------------------------------------------------
        // Load dictionary with test tile entry
        //----------------------------------------------------------------------
        $display("");
        $display("Loading dictionary entry for test tile...");

        set_bloom_for_hash(expected_hash);
        load_hash_entry(
            {expected_hash[7:0], 2'b00},  // bucket * 4 + chain 0
            expected_hash,
            8'h42,                         // char_code = 'B'
            16'h1234                       // translation_ptr
        );

        $display("Dictionary loaded.");
        repeat(10) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 1: End-to-end lookup (known tile)
        //----------------------------------------------------------------------
        $display("");
        $display("Test 1: End-to-end lookup (known tile)");

        cfg_enable = 1;
        write_tile_to_vram(9'd0);

        // Wait for pipeline to complete
        wait_for_lookup();

        if (match_found && char_code == 8'h42) begin
            $display("  PASS: match_found=%b, char_code=0x%02h, trans_ptr=0x%04h",
                     match_found, char_code, translation_ptr);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: match_found=%b, char_code=0x%02h (expected 0x42)",
                     match_found, char_code);
            fail_count = fail_count + 1;
        end

        repeat(20) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 2: Unknown tile (no match expected)
        //----------------------------------------------------------------------
        $display("");
        $display("Test 2: End-to-end lookup (unknown tile)");

        // Change tile data so hash won't match
        for (i = 0; i < 16; i = i + 1) begin
            test_tile[i] = 8'h55;
        end

        write_tile_to_vram(9'd1);
        wait_for_lookup();

        if (!match_found) begin
            $display("  PASS: No match found (as expected)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Unexpected match found");
            fail_count = fail_count + 1;
        end

        repeat(20) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 3: Multiple tiles in sequence
        //----------------------------------------------------------------------
        $display("");
        $display("Test 3: Multiple tile lookups in sequence");

        // First tile (matches)
        for (i = 0; i < 16; i = i + 1) begin
            test_tile[i] = 8'hA0 + i[7:0];
        end
        write_tile_to_vram(9'd2);
        wait_for_lookup();

        if (match_found && char_code == 8'h42) begin
            $display("  Tile 2: PASS (matched)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Tile 2: FAIL");
            fail_count = fail_count + 1;
        end

        repeat(10) @(posedge clk);

        // Second tile (no match)
        for (i = 0; i < 16; i = i + 1) begin
            test_tile[i] = 8'hFF;
        end
        write_tile_to_vram(9'd3);
        wait_for_lookup();

        if (!match_found) begin
            $display("  Tile 3: PASS (no match, as expected)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Tile 3: FAIL");
            fail_count = fail_count + 1;
        end

        repeat(10) @(posedge clk);

        // Third tile (matches)
        for (i = 0; i < 16; i = i + 1) begin
            test_tile[i] = 8'hA0 + i[7:0];
        end
        write_tile_to_vram(9'd4);
        wait_for_lookup();

        if (match_found && char_code == 8'h42) begin
            $display("  Tile 4: PASS (matched)");
            pass_count = pass_count + 1;
        end else begin
            $display("  Tile 4: FAIL");
            fail_count = fail_count + 1;
        end

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("");
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
        #2000000;
        $display("ERROR: Global timeout reached");
        $finish;
    end

endmodule
