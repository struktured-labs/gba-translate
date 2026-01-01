//------------------------------------------------------------------------------
// hash_lookup_table.sv
//
// Two-tier lookup system for Japanese character tile identification:
// 1. Bloom filter (fast reject for non-Japanese tiles)
// 2. Hash table (precise character matching)
//
// Bloom Filter:
//   - 8KB (65536 bits)
//   - 3 hash functions (variants of input hash)
//   - ~2% false positive rate at 3000 entries
//
// Hash Table:
//   - 4096 buckets (12-bit index)
//   - 4-entry chaining per bucket
//   - Entry format: {valid, hash[15:0], char_code[7:0], translation_ptr[15:0]}
//------------------------------------------------------------------------------

module hash_lookup_table #(
    parameter BLOOM_SIZE_BITS = 65536,      // 8KB
    parameter BLOOM_ADDR_BITS = 16,
    parameter TABLE_BUCKETS = 4096,
    parameter TABLE_ADDR_BITS = 12,
    parameter CHAIN_DEPTH = 4
) (
    input  logic        clk,
    input  logic        rst_n,

    // Hash input
    input  logic        hash_valid,
    input  logic [15:0] hash_in,

    // Match output
    output logic        match_found,
    output logic        lookup_done,
    output logic [7:0]  char_code,          // Matched character code
    output logic [15:0] translation_ptr,    // Pointer to translation string

    // External memory interface (for large dictionaries)
    output logic        ext_mem_rd,
    output logic [23:0] ext_mem_addr,
    input  logic [31:0] ext_mem_rdata,
    input  logic        ext_mem_rvalid,

    // Dictionary loading interface
    input  logic        dict_load_en,
    input  logic [15:0] dict_load_addr,
    input  logic [39:0] dict_load_data,     // {valid, hash, char_code, translation_ptr}
    input  logic        bloom_load_en,
    input  logic [15:0] bloom_load_addr,
    input  logic        bloom_load_bit
);

    //--------------------------------------------------------------------------
    // Bloom filter memory (8KB = 65536 bits)
    //--------------------------------------------------------------------------

    // Split into 4 BRAMs for parallel access (3 hash functions + 1 spare)
    logic bloom_mem [0:BLOOM_SIZE_BITS-1];

    // Three hash function variants for Bloom filter
    wire [15:0] bloom_hash1 = hash_in;
    wire [15:0] bloom_hash2 = {hash_in[7:0], hash_in[15:8]};  // Byte swap
    wire [15:0] bloom_hash3 = hash_in ^ 16'h5A5A;             // XOR constant

    logic bloom_bit1, bloom_bit2, bloom_bit3;
    logic bloom_positive;

    //--------------------------------------------------------------------------
    // Hash table memory
    // Each entry: {valid[1], hash[16], char_code[8], translation_ptr[16]} = 41 bits
    // Stored as 48 bits for alignment
    //--------------------------------------------------------------------------

    // Table entry structure
    typedef struct packed {
        logic        valid;
        logic [15:0] stored_hash;
        logic [7:0]  char_code;
        logic [15:0] trans_ptr;
    } table_entry_t;

    // Hash table with chaining (4 entries per bucket)
    table_entry_t hash_table [0:TABLE_BUCKETS*CHAIN_DEPTH-1];

    //--------------------------------------------------------------------------
    // State machine
    //--------------------------------------------------------------------------

    typedef enum logic [2:0] {
        IDLE,
        BLOOM_CHECK,
        TABLE_LOOKUP,
        CHAIN_SEARCH,
        DONE
    } state_t;

    state_t state, next_state;

    logic [15:0] current_hash;
    logic [11:0] table_bucket;
    logic [1:0]  chain_index;
    table_entry_t current_entry;

    //--------------------------------------------------------------------------
    // Bloom filter logic
    //--------------------------------------------------------------------------

    // Bloom filter reads (registered for timing)
    always_ff @(posedge clk) begin
        bloom_bit1 <= bloom_mem[bloom_hash1];
        bloom_bit2 <= bloom_mem[bloom_hash2];
        bloom_bit3 <= bloom_mem[bloom_hash3];
    end

    // Bloom positive if all three bits are set
    assign bloom_positive = bloom_bit1 && bloom_bit2 && bloom_bit3;

    // Bloom filter write (for loading)
    always_ff @(posedge clk) begin
        if (bloom_load_en) begin
            bloom_mem[bloom_load_addr] <= bloom_load_bit;
        end
    end

    //--------------------------------------------------------------------------
    // Hash table bucket calculation
    //--------------------------------------------------------------------------

    // Use lower 12 bits of hash for bucket index
    wire [11:0] hash_bucket = hash_in[11:0];

    //--------------------------------------------------------------------------
    // State machine
    //--------------------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            current_hash <= 16'h0;
            chain_index <= 2'b0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    if (hash_valid) begin
                        current_hash <= hash_in;
                        table_bucket <= hash_bucket;
                        chain_index <= 2'b0;
                    end
                end

                CHAIN_SEARCH: begin
                    if (chain_index < CHAIN_DEPTH - 1) begin
                        chain_index <= chain_index + 1;
                    end
                end
            endcase
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (hash_valid) begin
                    next_state = BLOOM_CHECK;
                end
            end

            BLOOM_CHECK: begin
                // Wait one cycle for bloom filter read
                next_state = bloom_positive ? TABLE_LOOKUP : DONE;
            end

            TABLE_LOOKUP: begin
                next_state = CHAIN_SEARCH;
            end

            CHAIN_SEARCH: begin
                // Read table entry
                if (current_entry.valid && current_entry.stored_hash == current_hash) begin
                    // Match found
                    next_state = DONE;
                end else if (chain_index == CHAIN_DEPTH - 1 || !current_entry.valid) begin
                    // End of chain or invalid entry
                    next_state = DONE;
                end
                // Otherwise continue searching chain
            end

            DONE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    //--------------------------------------------------------------------------
    // Hash table read
    //--------------------------------------------------------------------------

    wire [13:0] table_addr = {table_bucket, chain_index};

    always_ff @(posedge clk) begin
        current_entry <= hash_table[table_addr];
    end

    //--------------------------------------------------------------------------
    // Hash table write (for loading)
    //--------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (dict_load_en) begin
            hash_table[dict_load_addr[13:0]] <= '{
                valid:       dict_load_data[39],
                stored_hash: dict_load_data[38:23],
                char_code:   dict_load_data[22:15],
                trans_ptr:   dict_load_data[14:0]
            };
        end
    end

    //--------------------------------------------------------------------------
    // Output logic
    //--------------------------------------------------------------------------

    logic match_found_reg;
    logic [7:0] char_code_reg;
    logic [15:0] trans_ptr_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            match_found_reg <= 1'b0;
            char_code_reg <= 8'h0;
            trans_ptr_reg <= 16'h0;
        end else if (state == CHAIN_SEARCH &&
                     current_entry.valid &&
                     current_entry.stored_hash == current_hash) begin
            match_found_reg <= 1'b1;
            char_code_reg <= current_entry.char_code;
            trans_ptr_reg <= current_entry.trans_ptr;
        end else if (state == IDLE) begin
            match_found_reg <= 1'b0;
        end
    end

    assign lookup_done = (state == DONE);
    assign match_found = match_found_reg && (state == DONE);
    assign char_code = char_code_reg;
    assign translation_ptr = trans_ptr_reg;

    // External memory not used in this simple implementation
    assign ext_mem_rd = 1'b0;
    assign ext_mem_addr = 24'h0;

endmodule
