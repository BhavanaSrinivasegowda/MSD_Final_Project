/**
 * @file cache_simulator.sv
 * @brief Cache Simulator for ECE 485/585 Final Project
 * Xiang Li
 * This module simulates a last level cache (LLC) with MESI coherence protocol,
 * pseudo-LRU replacement policy, and supports bus operations and interactions
 * with higher-level caches.
 * MESI part is implemented in this file.
 * The cache is 16MB, 16-way set associative, with 64-byte lines.
 */

module cache_simulator;

    // Cache Parameters
    parameter ADDRESS_WIDTH = 32;                // Width of the memory addresses
    parameter CACHE_SIZE    = 16 * 1024 * 1024; // Total cache size in bytes (16MB)
    parameter LINE_SIZE     = 64;                // Size of each cache line in bytes
    parameter ASSOCIATIVITY = 16;                // Number of ways (16-way set associative)

    // Derived Parameters
    localparam NUM_LINES   = CACHE_SIZE / LINE_SIZE; // Total number of cache lines, 256K lines
    localparam NUM_SETS    = NUM_LINES / ASSOCIATIVITY; // Number of sets in the cache, 16K sets
    localparam OFFSET_BITS = $clog2(LINE_SIZE);         // Number of bits for offset within a cache line, 6 bits
    localparam INDEX_BITS  = $clog2(NUM_SETS);          // Number of bits for cache set index, 14 bits
    localparam TAG_BITS    = ADDRESS_WIDTH - INDEX_BITS - OFFSET_BITS; // Number of bits for tag, 12 bits

    // MESI Protocol States
    typedef enum logic [1:0] {
        INVALID   = 2'b00, // Invalid state
        SHARED    = 2'b01, // Shared state
        EXCLUSIVE = 2'b10, // Exclusive state
        MODIFIED  = 2'b11  // Modified state
    } MESI_State_t;

    // Cache Line Structure
    typedef struct packed {
        logic                 valid;       // Valid bit, indicating if the line contains valid data
        logic                 dirty;       // Dirty bit, For write-back policy
        logic [TAG_BITS-1:0]  tag;         // Tag bits of the address
        MESI_State_t          mesi_state;  // MESI coherence state of the cache line
    } CacheLine_t;

    // Cache Set Structure
    typedef struct {
        CacheLine_t lines [0:ASSOCIATIVITY-1];       // Array of cache lines in the set
        logic [ASSOCIATIVITY-2:0] lru_state;         // Pseudo-LRU bits for replacement policy, 15 bits per set
    } CacheSet_t;

    // Cache Structure
    typedef struct {
        CacheSet_t sets [0:NUM_SETS-1];              // Array of cache sets, 16K sets
    } Cache_t;

    // Cache Statistics Structure
    typedef struct {
        integer read_count;    // Number of cache read operations
        integer write_count;   // Number of cache write operations
        integer hit_count;     // Number of cache hits
        integer miss_count;    // Number of cache misses
    } CacheStats_t;

    // Bus Operation Types
    `define READ          1 // Bus Read
    `define WRITE         2 // Bus Write
    `define INVALIDATE    3 // Bus Invalidate
    `define RWIM          4 // Bus Read With Intent to Modify, invalidate other copies

    // Snoop Result Types
    `define NOHIT         0 // No Hit
    `define HIT           1 // Hit
    `define HITM          2 // Hit to Modified Line, need to write back

    // Message Types to Higher-Level Cache
    `define GETLINE          1 // Request data for modified line in L1
    `define SENDLINE         2 // Send requested cache line to L1
    `define INVALIDATELINE   3 // Invalidate a line in L1
    `define EVICTLINE        4 // Evict a line from L1
    // this is when L2's replacement policy causes eviction of a line that
    // may be present in L1. It could be done by a combination of GETLINE
    // (if the line is potentially modified in L1) and INVALIDATELINE.

    // Mode Control
    logic NormalMode; // Simulation mode: 1 for normal mode, 0 for silent mode

    // Global Variables
    Cache_t cache;      // The cache instance
    CacheStats_t stats; // Cache statistics

    /** 
     * @brief Initializes the cache by setting all lines to invalid and resetting statistics.
     */
    task initialize_cache();
        integer set_index, line_index;
        begin
            // Iterate over all cache sets
            for (set_index = 0; set_index < NUM_SETS; set_index = set_index + 1) begin
                // Initialize pseudo-LRU bits for the set
                cache.sets[set_index].lru_state = '0;
                // Iterate over all cache lines in the set
                for (line_index = 0; line_index < ASSOCIATIVITY; line_index = line_index + 1) begin
                    cache.sets[set_index].lines[line_index].valid      = 0;
                    cache.sets[set_index].lines[line_index].dirty      = 0;
                    cache.sets[set_index].lines[line_index].tag        = '0;
                    cache.sets[set_index].lines[line_index].mesi_state = INVALID;
                end
            end
            // Reset cache statistics
            stats.read_count  = 0;
            stats.write_count = 0;
            stats.hit_count   = 0;
            stats.miss_count  = 0;
        end
    endtask

    /**
     * @brief Clears the cache and resets all state.
     */
    task clear_cache();
        begin
            initialize_cache();
        end
    endtask

    /**
     * @brief Prints the contents and state of each valid cache line.
     */
    task print_cache_contents();
        integer set_index, line_index;
        begin
            $display("Valid Cache Lines:");
            for (set_index = 0; set_index < NUM_SETS; set_index = set_index + 1) begin
                for (line_index = 0; line_index < ASSOCIATIVITY; line_index = line_index + 1) begin
                    if (cache.sets[set_index].lines[line_index].valid) begin
                        $display("Set: %0d, Way: %0d, Tag: %h, MESI: %0d, Dirty: %0d",
                                 set_index, line_index, cache.sets[set_index].lines[line_index].tag,
                                 cache.sets[set_index].lines[line_index].mesi_state,
                                 cache.sets[set_index].lines[line_index].dirty);
                    end
                end
            end
        end
    endtask

    // Function to extract tag, index, and offset
    function void decode_address(input logic [ADDRESS_WIDTH-1:0] address,
                                 output logic [TAG_BITS-1:0] tag,
                                 output logic [INDEX_BITS-1:0] index,
                                 output logic [OFFSET_BITS-1:0] offset);
        begin
            offset = address[OFFSET_BITS-1:0];
            index  = address[OFFSET_BITS + INDEX_BITS -1 : OFFSET_BITS];
            tag    = address[ADDRESS_WIDTH-1 : ADDRESS_WIDTH - TAG_BITS];
        end
    endfunction

//Inside cache ACCESS
    // MESI State Update Functions

    /**
     * @brief Updates the MESI state on a read hit.
     * @param line_index The index of the cache line within the set.
     * @param index The cache set index.
     *
     * This should be used in the read operation on a read hit. For misses MSEI shoule be handled inside the read operation.
     * This function updates the MESI state of a cache line when a read hit occurs. At a read Hit, the state should remain the same.
     */
    task update_mesi_state_on_hit_read(integer line_index, logic [INDEX_BITS-1:0] index);
        begin
            case (cache.sets[index].lines[line_index].mesi_state)
                EXCLUSIVE: begin
                    // Remain in EXCLUSIVE state
                end
                MODIFIED: begin
                    // Remain in MODIFIED state
                end
                SHARED: begin
                    // Remain in SHARED state
                end
                INVALID: begin
                    // Should not occur, as we have a hit, report error
                error("Invalid MESI state on read hit");
                end
            endcase
        end
    endtask

    /**
     * @brief Updates the MESI state on a write hit.
     * @param line_index The index of the cache line within the set.
     * @param index The cache set index.
     * @param address The memory address being written.
     *
     * This function updates the MESI state of a cache line when a write hit occurs.
     */
    task update_mesi_state_on_hit_write(integer line_index, logic [INDEX_BITS-1:0] index, logic [ADDRESS_WIDTH-1:0] address);
        int snoop_result;
        begin
            case (cache.sets[index].lines[line_index].mesi_state)
                SHARED: begin
                    // Issue RWIM bus operation to invalidate other copies
                    BusOperation(`RWIM, address, snoop_result);
                    cache.sets[index].lines[line_index].mesi_state = MODIFIED;
                end
                EXCLUSIVE: begin
                    // Transition to MODIFIED state
                    cache.sets[index].lines[line_index].mesi_state = MODIFIED;
                end
                MODIFIED: begin
                    // Remain in MODIFIED state
                end
                INVALID: begin
                    // Should not occur, as we have a hit
                end
            endcase
        end
    endtask

    /**
     * @brief Simulates a bus operation initiated by our cache.
     * @param BusOp The bus operation type (READ, WRITE, INVALIDATE, RWIM).
     * @param Address The memory address involved in the operation.
     * @param SnoopResult Output parameter to capture snoop results from other caches.
     *
     * This function simulates bus operations, gets snoop results from other caches,
     * and prints the operation if in NormalMode.
     */
    task BusOperation(int BusOp, logic [ADDRESS_WIDTH-1:0] Address, output int SnoopResult);
        begin
            SnoopResult = GetSnoopResult(Address);
            if (NormalMode) begin
                $display("BusOp: %0d, Address: %h, Snoop Result: %0d", BusOp, Address, SnoopResult);
            end
        end
    endtask

    /**
     * @brief Simulates getting snoop results from other caches.
     * @param Address The memory address being snooped.
     * @return SnoopResult The snoop result (HIT, NOHIT, HITM).
     *
     * This function can be modified to simulate different snoop results for testing purposes.
     */
    function int GetSnoopResult(logic [ADDRESS_WIDTH-1:0] Address);
        begin
            // need modification!
            return `NOHIT;
        end
    endfunction

    /**
     * @brief Reports our snoop result to the bus in response to snooped bus operations.
     * @param Address The memory address involved.
     * @param SnoopResult The snoop result to report.
     *
     * This function prints our snoop result if in NormalMode.
     */
    task PutSnoopResult(logic [ADDRESS_WIDTH-1:0] Address, int SnoopResult);
        begin
            if (NormalMode) begin
                $display("SnoopResult: Address %h, SnoopResult: %0d", Address, SnoopResult);
            end
        end
    endtask

    /**
     * @brief Simulates communication with the higher-level cache.
     * @param Message The message type to send.
     * @param Address The memory address involved.
     *
     * This function prints the message if in NormalMode.
     */
    task MessageToCache(int Message, logic [ADDRESS_WIDTH-1:0] Address);
        begin
            if (NormalMode) begin
                $display("L2: %0d %h", Message, Address);
            end
        end
    endtask

    /**
     * @brief Processes snooped bus operations from other processors.
     * @param opcode The operation code indicating the type of snooped operation.
     * @param address The memory address involved in the snooped operation.
     *
     * This function updates the MESI state of cache lines in response to snooped bus operations.
     */
    task process_snooped_bus_operation(input int opcode, input logic [ADDRESS_WIDTH-1:0] address);
        logic [TAG_BITS-1:0]    tag;
        logic [INDEX_BITS-1:0]  index;
        logic [OFFSET_BITS-1:0] offset;
        integer line_index;
        bit hit;
        int snoop_result;
        begin
            // First decode the address to get tag, index, and offset
            decode_address(address, tag, index, offset);
            // Initialize snoop result
            hit = 0;
            snoop_result = `NOHIT;
            // Search for matching cache line
            for (line_index = 0; line_index < ASSOCIATIVITY; line_index = line_index + 1) begin
                if (cache.sets[index].lines[line_index].valid &&
                    cache.sets[index].lines[line_index].tag == tag) begin
                    hit = 1;
                    // Perform actions based on opcode and MESI state
                    case (opcode)
                        3: begin // Snooped READ, if line is MODIFIED, write back
                            if (cache.sets[index].lines[line_index].mesi_state == MODIFIED) begin
                                // Simulate write-back to memory
                                BusOperation(`WRITE, address, snoop_result);
                                cache.sets[index].lines[line_index].mesi_state = SHARED;
                                cache.sets[index].lines[line_index].dirty = 0;
                                snoop_result = `HITM;
                            end else if (cache.sets[index].lines[line_index].mesi_state == EXCLUSIVE) begin
                                cache.sets[index].lines[line_index].mesi_state = SHARED;
                                snoop_result = `HIT;
                            end else begin
                                // SHARED or INVALID state
                                snoop_result = `HIT;
                            end
                        end
                        4,5,6: begin // Snooped WRITE, RWIM, INVALIDATE
                            cache.sets[index].lines[line_index].valid      = 0;
                            cache.sets[index].lines[line_index].dirty      = 0;
                            cache.sets[index].lines[line_index].mesi_state = INVALID;
                            snoop_result = `HIT;
                        end
                        default: begin
                            // Other opcodes, doesn't related to BUS
                        end
                    endcase
                    // Report our snoop result
                    PutSnoopResult(address, snoop_result);
                    break;
                end
            end
            if (!hit) begin
                // Didn't HIT
                snoop_result = `NOHIT;
                PutSnoopResult(address, snoop_result);
            end
        end
    endtask
