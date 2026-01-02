`timescale 1ns / 1ps
//------------------------------------------------------------------------------
// tb_vram_snooper.sv
//
// Testbench for vram_snooper module.
// Verifies tile capture and streaming behavior.
// Compatible with Icarus Verilog.
//------------------------------------------------------------------------------

module tb_vram_snooper;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam TILE_SIZE = 16;  // GB 2bpp tiles are 16 bytes

    //--------------------------------------------------------------------------
    // DUT signals
    //--------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;

    // VRAM interface
    reg         vram_we;
    reg  [12:0] vram_addr;
    reg  [7:0]  vram_wdata;

    // Tile capture outputs
    wire        tile_capture_done;
    wire [8:0]  tile_index;
    wire        tile_is_text_region;

    // Hash generator interface
    wire        hash_data_valid;
    wire [7:0]  hash_data;
    wire        hash_data_last;

    // Configuration
    reg         cfg_enable;
    reg  [8:0]  cfg_text_tile_start;
    reg  [8:0]  cfg_text_tile_end;

    //--------------------------------------------------------------------------
    // DUT instantiation
    //--------------------------------------------------------------------------
    vram_snooper #(
        .TILE_SIZE_BYTES(TILE_SIZE)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .vram_we            (vram_we),
        .vram_addr          (vram_addr),
        .vram_wdata         (vram_wdata),
        .tile_capture_done  (tile_capture_done),
        .tile_index         (tile_index),
        .tile_is_text_region(tile_is_text_region),
        .hash_data_valid    (hash_data_valid),
        .hash_data          (hash_data),
        .hash_data_last     (hash_data_last),
        .cfg_enable         (cfg_enable),
        .cfg_text_tile_start(cfg_text_tile_start),
        .cfg_text_tile_end  (cfg_text_tile_end)
    );

    //--------------------------------------------------------------------------
    // Clock generation
    //--------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Test variables
    //--------------------------------------------------------------------------
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [7:0] captured_bytes [0:TILE_SIZE-1];
    integer captured_count;
    reg [7:0] test_tile [0:TILE_SIZE-1];
    integer i;
    reg capture_done_flag;
    reg tile_done_seen;

    //--------------------------------------------------------------------------
    // Capture tile_capture_done pulse (only 1 cycle)
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            tile_done_seen <= 0;
        else if (tile_capture_done)
            tile_done_seen <= 1;
    end

    //--------------------------------------------------------------------------
    // Task: Write a single byte to VRAM
    //--------------------------------------------------------------------------
    task vram_write;
        input [12:0] addr;
        input [7:0] data;
        begin
            @(posedge clk);
            vram_we <= 1'b1;
            vram_addr <= addr;
            vram_wdata <= data;
            @(posedge clk);
            vram_we <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Task: Write a complete tile (16 bytes)
    //--------------------------------------------------------------------------
    task write_tile;
        input [8:0] tile_idx;
        reg [12:0] base_addr;
        integer j;
        begin
            base_addr = {tile_idx, 4'b0000};  // tile_idx * 16
            for (j = 0; j < TILE_SIZE; j = j + 1) begin
                vram_write(base_addr + j, test_tile[j]);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // Capture process - runs in parallel with write
    //--------------------------------------------------------------------------
    always @(posedge clk) begin
        if (hash_data_valid && captured_count < TILE_SIZE) begin
            captured_bytes[captured_count] <= hash_data;
            captured_count <= captured_count + 1;
            if (hash_data_last) begin
                capture_done_flag <= 1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_vram_snooper.vcd");
        $dumpvars(0, tb_vram_snooper);

        $display("========================================");
        $display("VRAM Snooper Testbench");
        $display("========================================");
        $display("");

        // Initialize
        rst_n = 0;
        vram_we = 0;
        vram_addr = 0;
        vram_wdata = 0;
        cfg_enable = 1;
        cfg_text_tile_start = 9'd32;   // Tiles 32-127 are "text" region
        cfg_text_tile_end = 9'd127;
        pass_count = 0;
        fail_count = 0;
        captured_count = 0;
        capture_done_flag = 0;
        tile_done_seen = 0;

        // Reset
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 1: Write sequential tile data
        //----------------------------------------------------------------------
        $display("Test 1: Sequential tile data to tile 0");
        for (i = 0; i < TILE_SIZE; i = i + 1) test_tile[i] = i;
        captured_count = 0;
        capture_done_flag = 0;
        tile_done_seen = 0;

        write_tile(9'd0);

        // Wait for capture done
        repeat(50) @(posedge clk);

        if (tile_done_seen) begin
            $display("  Tile index: %0d (expected 0)", tile_index);
            if (tile_index == 9'd0) begin
                $display("  PASS: Tile 0 captured correctly");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: Wrong tile index");
                fail_count = fail_count + 1;
            end
        end else begin
            $display("  FAIL: tile_capture_done was never asserted");
            fail_count = fail_count + 1;
        end

        repeat(20) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 2: Tile in text region
        //----------------------------------------------------------------------
        $display("");
        $display("Test 2: Tile in text region (tile 64)");
        for (i = 0; i < TILE_SIZE; i = i + 1) test_tile[i] = 8'hAA;
        captured_count = 0;
        capture_done_flag = 0;

        write_tile(9'd64);  // Tile 64 is in text region (32-127)

        repeat(50) @(posedge clk);

        if (tile_is_text_region && tile_index == 9'd64) begin
            $display("  tile_is_text_region: %b", tile_is_text_region);
            $display("  PASS: Text region flag set correctly");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: tile_is_text_region=%b, tile_index=%0d",
                     tile_is_text_region, tile_index);
            fail_count = fail_count + 1;
        end

        repeat(20) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 3: Tile outside text region
        //----------------------------------------------------------------------
        $display("");
        $display("Test 3: Tile outside text region (tile 200)");
        for (i = 0; i < TILE_SIZE; i = i + 1) test_tile[i] = 8'h55;
        captured_count = 0;
        capture_done_flag = 0;

        write_tile(9'd200);  // Tile 200 is outside text region

        repeat(50) @(posedge clk);

        if (!tile_is_text_region && tile_index == 9'd200) begin
            $display("  tile_is_text_region: %b", tile_is_text_region);
            $display("  PASS: Text region flag correctly not set");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: tile_is_text_region=%b, tile_index=%0d",
                     tile_is_text_region, tile_index);
            fail_count = fail_count + 1;
        end

        repeat(20) @(posedge clk);

        //----------------------------------------------------------------------
        // Test 4: Hash data streaming
        //----------------------------------------------------------------------
        $display("");
        $display("Test 4: Verify hash data stream output");
        for (i = 0; i < TILE_SIZE; i = i + 1) test_tile[i] = i + 8'h10;
        captured_count = 0;
        capture_done_flag = 0;

        write_tile(9'd5);

        // Wait for streaming to complete
        repeat(100) @(posedge clk);

        $display("  Captured %0d bytes", captured_count);
        if (captured_count == TILE_SIZE) begin
            $display("  PASS: All 16 bytes streamed");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: Expected 16 bytes, got %0d", captured_count);
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
        #500000;  // 500us timeout
        $display("ERROR: Global timeout reached");
        $finish;
    end

endmodule
