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
    int snoop_result;   // Snoop result for bus operations

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
                    if (cache.sets[set_index].lines[line_index].mesi_state != INVALID) begin
                        $display("Set: %0d, Way: %0d, Tag: %h, MESI: %s",
                                 set_index, line_index, cache.sets[set_index].lines[line_index].tag,
                                 mesi_state_to_string(cache.sets[set_index].lines[line_index].mesi_state));
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


// Function for bus operations
// Get snoop result
function int get_snoop_result_out(input logic [ADDRESS_WIDTH-1:0] address);
    case (address[1:0])
        2'b00: get_snoop_result = `HIT;   // ---00 = HIT
        2'b01: get_snoop_result = `HITM;  // ---01 = HITM
        default: get_snoop_result = `NOHIT; // ---10 or ---11 = NOHIT
    endcase
endfunction

// Report the result of our snooping bus operations performed by other caches 
task PutSnoopResult(input [ADDRESS_WIDTH-1:0] address, input int SnoopResult);
    if (NormalMode) begin
        $display("SnoopResult: Address %h, SnoopResult: %s",
                 Address, snoop_result_to_string(SnoopResult));
     end
endtask

// Function to convert MESI state to string
function string mesi_state_to_string(input logic [1:0] mesi_state);
    case (mesi_state)
        `INVALID:   mesi_state_to_string = "INVALID";
        `EXCLUSIVE: mesi_state_to_string = "EXCLUSIVE";
        `SHARED:    mesi_state_to_string = "SHARED";
        `MODIFIED:  mesi_state_to_string = "MODIFIED";
        default:    mesi_state_to_string = "UNKNOWN";
    endcase
endfunction

// Function to convert snoop result to string
function string snoop_result_to_string(input int snoop_result);
    case (snoop_result)
        `NOHIT: snoop_result_to_string = "NOHIT";
        `HIT:   snoop_result_to_string = "HIT";
        `HITM:  snoop_result_to_string = "HITM";
        default: snoop_result_to_string = "UNKNOWN";
    endcase
endfunction

// Function to convert BusOp to string
    function string bus_op_to_string(input int BusOp);
        case (BusOp)
            `READ:       bus_op_to_string = "READ";
            `WRITE:      bus_op_to_string = "WRITE";
            `INVALIDATE: bus_op_to_string = "INVALIDATE";
            `RWIM:       bus_op_to_string = "RWIM";
            default:     bus_op_to_string = "UNKNOWN";
        endcase
    endfunction
// Bus Operations
    /**
     * @brief Task to simulate a bus operation and capture the snoop results of last level 
     *        caches of other processors. SnoopResult is printed as a string.
     * @param BusOp       The type of bus operation (READ, WRITE, INVALIDATE, RWIM)
     * @param Address     The memory address involved in the bus operation
     * @param SnoopResult The result of the snoop operation (NOHIT, HIT, HITM)
     */
    task BusOperation(input int BusOp, input logic [ADDRESS_WIDTH-1:0] Address, input int SnoopResult);
        if (NormalMode) begin
            $display("BusOp: %s, Address: %h, Snoop Result: %s",
                     bus_op_to_string(BusOp), Address, snoop_result_to_string(SnoopResult));
        end
    endtask


// Case 3: Snooped read request
//Check index and tag if the address exists.
//	Put snoop result (HIT,HITM,NOHIT)
//	IF HIT , the line in E state -> S, Read form DRAM
//		 S -> S  
//	IF HITM M ->S, Bus write,
//	NoHit.
task Snooped_read_request(input logic [ADDRESS_WIDTH-1:0] address);
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    integer set_index, line_index;
    begin
        decode_address(address, tag, index, offset);
        // Iterate over all cache lines in the set
        for (line_index = 0; line_index < ASSOCIATIVITY; line_index = line_index + 1) begin
            if (cache.sets[index].lines[line_index].tag == tag) begin
                // Hit
                IF (cache.sets[index].lines[line_index].mesi_state == `EXCLUSIVE) begin
                    cache.sets[index].lines[line_index].mesi_state = `SHARED;
                    PutSnoopResult(address, `HIT);
                end
                ELSE IF (cache.sets[index].lines[line_index].mesi_state == `SHARED) begin
                    PutSnoopResult(address, `HIT);
                end
                ELSE IF (cache.sets[index].lines[line_index].mesi_state == `MODIFIED) begin
                    cache.sets[index].lines[line_index].mesi_state = `SHARED;
                    PutSnoopResult(address, `HITM);
                    BusOperation(`WRITE, address, `HITM);
                end
                ELSE begin
                    PutSnoopResult(address, `NOHIT);
                end
            end
        end
    end
endtask

// Case 4: Snooped write request(Saw an FlushWB,Flush)
// Print a message that snooped a write request and its address
task Snooped_write_request(input logic [ADDRESS_WIDTH-1:0] address);
    begin
        if (NormalMode) begin
            $display("Snooped write request at address %h", address);
        end
    end
endtask

// Case 5: snooped read with intent to modify request
// Seacrh for the line in the cache, if it exixts in E,S state, invilidate it and send messgae
