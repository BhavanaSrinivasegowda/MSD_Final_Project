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

module cache_simulator1;

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
        CacheLine_t lines [ASSOCIATIVITY-1:0];       // Array of cache lines in the set
        logic [ASSOCIATIVITY-2:0] lru_state;         // Pseudo-LRU bits for replacement policy, 15 bits per set
    } CacheSet_t;

    // Cache Structure
    typedef struct {
        CacheSet_t sets [0:NUM_SETS-1];              // Array of cache sets, 16K sets
    } Cache_t;

    // Cache Statistics Structure
    typedef struct {
        integer read_count = 0;    // Number of cache read operations
        integer write_count = 0;   // Number of cache write operations
        integer hit_count = 0;     // Number of cache hits
        integer miss_count = 0;    // Number of cache misses
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
     // Without resetting the statistics
     */
    task clear_cache();
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
        end
    endtask

    /**
     * @brief Prints the contents and state of each valid cache line.
     */
    task print_cache_contents();
        integer set_index, line_index;
        real hit_ratio;
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
           // Calculate hit ratio
        if ((stats.read_count + stats.write_count) > 0) begin
            hit_ratio = (stats.hit_count * 100.0) / (stats.read_count + stats.write_count);
        end else begin
            hit_ratio = 0.0;
        end
        // Print cache statistics
        $display("\nCache Statistics:");
        $display("Number of cache reads: %0d", stats.read_count);
        $display("Number of cache writes: %0d", stats.write_count);
        $display("Number of cache hits: %0d", stats.hit_count);
        $display("Number of cache misses: %0d", stats.miss_count);
        $display("Cache hit ratio: %0.2f%%", hit_ratio);
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
int get_snoop_result;
    case (address[1:0])
        2'b00: get_snoop_result_out = `HIT;   // ---00 = HIT
        2'b01: get_snoop_result_out = `HITM;  // ---01 = HITM
        default: get_snoop_result_out = `NOHIT; // ---10 or ---11 = NOHIT
    endcase
endfunction

// Report the result of our snooping bus operations performed by other caches 
task PutSnoopResult(input [ADDRESS_WIDTH-1:0] address, input int SnoopResult);
    if (NormalMode) begin
        $display("SnoopResult: Address %h, SnoopResult: %s", address, snoop_result_to_string(SnoopResult));
     end
endtask

// Function to convert MESI state to string
function string mesi_state_to_string(input logic [1:0] mesi_state);
    case (mesi_state)
        INVALID:     mesi_state_to_string = "INVALID";
        EXCLUSIVE:   mesi_state_to_string = "EXCLUSIVE";
        SHARED:      mesi_state_to_string = "SHARED";
        MODIFIED:    mesi_state_to_string = "MODIFIED";
        default:     mesi_state_to_string = "UNKNOWN";
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

// Function to convert Message type to string
function string message_to_string(input int Message);
    case (Message)
        `GETLINE:         message_to_string = "GETLINE";
        `SENDLINE:        message_to_string = "SENDLINE";
        `INVALIDATELINE:  message_to_string = "INVALIDATELINE";
        `EVICTLINE:       message_to_string = "EVICTLINE";
        default:           message_to_string = "UNKNOWN";
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
/**
 * @brief Task to simulate communication to the upper-level cache (e.g., L1).
 *        It converts the message type to a string and prints the message along with the address.
 * @param Message The type of message (GETLINE, SENDLINE, INVALIDATELINE, EVICTLINE)
 * @param Address The memory address involved in the message
 */
task MessageToCache(
    input int Message,
    input logic [ADDRESS_WIDTH-1:0] Address
);
    if (NormalMode) begin
        $display("L2: %s %h",
                 message_to_string(Message), Address);
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
    
        decode_address(address, tag, index, offset);
        // Iterate over all cache lines in the set
        for (line_index = 0; line_index < ASSOCIATIVITY; line_index = line_index + 1) begin
            if (cache.sets[index].lines[line_index].tag == tag) begin
                // Hit
                if (cache.sets[index].lines[line_index].mesi_state == EXCLUSIVE) begin
                    cache.sets[index].lines[line_index].mesi_state = SHARED;
                    PutSnoopResult(address, `HIT);
                end
                else if (cache.sets[index].lines[line_index].mesi_state == SHARED) begin
                    PutSnoopResult(address, `HIT);
                end
                else if (cache.sets[index].lines[line_index].mesi_state == MODIFIED) begin
                    cache.sets[index].lines[line_index].mesi_state = SHARED;
                    PutSnoopResult(address, `HITM);
                    BusOperation(`WRITE, address, `HITM);
                end
                else begin
                    PutSnoopResult(address, `NOHIT);
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
// Seacrh for the line in the cache, if it exixts in E,S state, invilidate it and send messgae to L1
// If it is in M state, do Bus write, and Getline and Invalidate to L1
task Snooped_RWIM_request(input logic [ADDRESS_WIDTH-1:0] address);
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    integer set_index, line_index;
    decode_address(address, tag, index, offset);
        // Iterate over all cache lines in the set
        for (line_index = 0; line_index < ASSOCIATIVITY; line_index = line_index + 1) begin
            if (cache.sets[index].lines[line_index].tag == tag) begin
                // Hit
                if (cache.sets[index].lines[line_index].mesi_state == EXCLUSIVE) begin
                    cache.sets[index].lines[line_index].mesi_state = INVALID;
                    MessageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                else if (cache.sets[index].lines[line_index].mesi_state == SHARED) begin
                    cache.sets[index].lines[line_index].mesi_state = INVALID;
                    MessageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                else if (cache.sets[index].lines[line_index].mesi_state == MODIFIED) begin
                    BusOperation(`WRITE, address, `RWIM);
                    MessageToCache(`GETLINE, address);
                    MessageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HITM);
                end
                else begin
                    PutSnoopResult(address,`NOHIT);
                end
            end
        end
endtask

// Case 6: snooped invalidate request
// Search for the line, if in E,S, Hit and invalidate it. Send message to L1
// If in M, HITM and invalidate it, send message to L1
task Snooped_invalidate_request(input logic [ADDRESS_WIDTH-1:0] address);
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
                if (cache.sets[index].lines[line_index].mesi_state == EXCLUSIVE) begin
                    cache.sets[index].lines[line_index].mesi_state = INVALID;
                    MessageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                else if (cache.sets[index].lines[line_index].mesi_state == SHARED) begin
                    cache.sets[index].lines[line_index].mesi_state = INVALID;
                    MessageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                else if (cache.sets[index].lines[line_index].mesi_state == MODIFIED) begin
                    cache.sets[index].lines[line_index].mesi_state = INVALID;
                    MessageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HITM);
                end
                else begin
                    PutSnoopResult(address, `NOHIT);
                end
            end
        end
    end
endtask

function integer select_victim_line(input logic [INDEX_BITS-1:0] set_index);
    integer node_index;
    integer level;
    integer bit1;
    integer bit_length;
    integer victim_line;
    begin
        node_index = 0; // Start at the root of the tree
        bit_length = $clog2(ASSOCIATIVITY); // Number of bits in the pseudo LRU tree, 4 bits for 16-way

        // Traverse the pseudo LRU tree to update the LRU bits
        for (level = 0; level < bit_length; level++) begin
            // Determine the bit1 to access based on the level
            bit1 = cache.sets[set_index].lru_state[node_index];
            $display("Node: %0d LUR bits: %0d", node_index , bit1);

            if (bit1 == 1) begin
                // Update the LRU bit1 to 0
                // cache.sets[set_index].lru_state[node_index] = 0;
                // Move to the left child
                node_index = 2 * node_index + 1;
            end else begin
                // Update the LRU bit1 to 1
                // cache.sets[set_index].lru_state[node_index] = 1;
                // Move to the right child
                node_index = 2 * node_index + 2;
            end
        end
        victim_line = node_index - (2**bit_length - 1);
        select_victim_line = victim_line;
        $display("Selected victim line: %0d", select_victim_line);
    end
endfunction


    // Function to update the pseudo LRU bits after accessing a cache line
task update_lru_on_access(input logic [INDEX_BITS-1:0] set_index, input integer accessed_index);
    integer node_index;
    integer level;
    integer bit1;
    integer bit_length;
    begin
        node_index = 0; // Start at the root of the tree
        bit_length = $clog2(ASSOCIATIVITY); // Number of bits in the pseudo LRU tree, 4 bits for 16-way

        // Traverse the pseudo LRU tree to update the LRU bits
        for (level = 0; level < bit_length; level++) begin
            // Determine the bit1 to access based on the level
            bit1 = (accessed_index >> (bit_length - 1 - level)) & 1;

            if (bit1 == 0) begin
                // Update the LRU bit1 to 0
                cache.sets[set_index].lru_state[node_index] = 0;
                // Move to the left child
                node_index = 2 * node_index + 1;
            end else begin
                // Update the LRU bit1 to 1
                cache.sets[set_index].lru_state[node_index] = 1;
                // Move to the right child
                node_index = 2 * node_index + 2;
            end
        end
        $display("Updated LRU state for set %0d to %b ", set_index, cache.sets[set_index].lru_state);
    end
endtask

task process_write_request_data_cache(input logic [ADDRESS_WIDTH-1:0] address);
    // Variable declarations
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    integer line_index;
    logic hit;
    integer snoop_result;
    integer replacement_line;

    // Decode the address into tag, index, and offset
    decode_address(address, tag, index, offset);

    // Update the write count
    stats.write_count++;
    hit = 0; // Initialize hit flag

    // Search for the tag in the set
    for (line_index = 0; line_index < ASSOCIATIVITY; line_index++) begin
        if (cache.sets[index].lines[line_index].mesi_state != INVALID &&
            cache.sets[index].lines[line_index].tag == tag) begin
            // Cache hit
            hit = 1;
            stats.hit_count++;
            // Handle MESI state transitions
            case (cache.sets[index].lines[line_index].mesi_state)
                SHARED: begin
                    // Need to invalidate other caches
                    BusOperation(`INVALIDATE, address, `HIT);
                    cache.sets[index].lines[line_index].mesi_state = MODIFIED;
                end
                EXCLUSIVE: begin
                    cache.sets[index].lines[line_index].mesi_state = MODIFIED;
                    $display("Cache line in EXCLUSIVE state, transitioning to MODIFIED state.");
                end
                MODIFIED: begin
                    // Already in MODIFIED state, no action needed
                    $display("Cache line already in MODIFIED state, no action needed.");
                end
            endcase
            // Update the LRU state
            update_lru_on_access(index, line_index);
            break; // Exit the loop on hit
        end
    end

    if (!hit) begin
        // Cache miss
        stats.miss_count++;
        // Get snoop result from other caches
        snoop_result = get_snoop_result_out(address);
        // Issue Bus Read With Intent to Modify (RWIM)
        BusOperation(`RWIM, address, snoop_result);

        // Find a replacement line
        line_index = find_space(index,address);
        // Update the cache line
        cache.sets[index].lines[line_index].tag = tag;
        cache.sets[index].lines[line_index].mesi_state = MODIFIED;

        // Update the LRU state
        update_lru_on_access(index, line_index);

        // Send message to the cache
        MessageToCache(`SENDLINE, address);
    end
endtask



task process_read_request_L1_DataCache(input logic [ADDRESS_WIDTH-1:0] address);
    // Variable declarations
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    integer line_index;
    logic hit;
    integer snoop_result;
    integer replacement_line;
    
    // decode the address
    decode_address(address, tag, index, offset);
    
    // Update the read count
    stats.read_count++;
    hit = 0; // Cache hit flag

    // Search for the tag in the set
    for (line_index = 0; line_index < ASSOCIATIVITY; line_index++) begin
        if (cache.sets[index].lines[line_index].mesi_state != INVALID && 
            cache.sets[index].lines[line_index].tag == tag) begin
            // Cache hit
            hit = 1;
            stats.hit_count++;
            // Update the LRU state
            update_lru_on_access(index, line_index);
            break; // Exit the loop
        end
    end

    if (!hit) begin
        // Cache miss
        stats.miss_count++;

        // Check if the cache line is dirty
        snoop_result = get_snoop_result_out(address);

        if (snoop_result == `HIT || snoop_result == `HITM) begin
            // Bus read operation
            BusOperation(`READ, address, snoop_result);
            // Find a replacement line
            line_index = find_space(index,address);
            // Update the cache line
            cache.sets[index].lines[line_index].tag = tag;
            cache.sets[index].lines[line_index].mesi_state  = SHARED;
            // Send message to the cache
            MessageToCache(`SENDLINE, address);
        end else if (snoop_result == `NOHIT) begin
            // Bus read operation
            BusOperation(`READ, address, `NOHIT);
            line_index = find_space(index,address);
            // Update the cache line
            cache.sets[index].lines[line_index].tag = tag;
            cache.sets[index].lines[line_index].mesi_state = EXCLUSIVE;
            // Send message to the cache
            MessageToCache(`SENDLINE, address);
        end
        // Update the LRU state
        update_lru_on_access(index, line_index);
    end
endtask
//--------------------------------------------------------------------------------------------------------------------------------------------------
  
// findspace 
function int find_space(logic [INDEX_BITS-1:0] index, logic [ADDRESS_WIDTH-1:0] address);   
int empty_line;
int z;

for (int line_index = 0; line_index < ASSOCIATIVITY; line_index++) begin
    if (cache.sets[index].lines[line_index].mesi_state == INVALID)begin
     empty_line = line_index;
     return empty_line;
    end
end
    
     z = select_victim_line(index);
     evict_line(index, z, address);
     return z;
endfunction 


  // Function to return data to L1
function void return_data_to_L1(input logic [ADDRESS_WIDTH-1:0] address);
    // Here, you would typically send the data back to the L1 cache.
    // For simulation purposes, we can just print the address and data.
    $display("Returning data to L1: Address = %h", address);
endfunction


    // Evict a cache line using LRU policy
function evict_line(input logic [INDEX_BITS-1:0] index, int line_index, logic [ADDRESS_WIDTH-1:0] address); 
    if (cache.sets[index].lines[line_index].mesi_state == MODIFIED) begin
    //write to DRAM function 
    BusOperation(`WRITE, address, `NOHIT);
    cache.sets[index].lines[line_index].mesi_state = INVALID;
    $display("%h is evicted from the cache", address);
    MessageToCache(`EVICTLINE, address);
    end
    else begin
    end
endfunction

task read_request_from_L1_Instruction_cache(input logic [ADDRESS_WIDTH -1 :0] address);
        process_read_request_L1_DataCache(address);
endtask
//Simulation Control and Trace File Processing
    /**
     * @brief Processes the trace file containing memory operations.
     * @param filename The name of the trace file to process.
     *
     * This function reads memory operations from the trace file and dispatches them
     * to the appropriate handlers.
     */

    
    /**
     * @brief Main simulation control.
     *
     * This initial block coordinates the overall simulation, including initialization,
     * processing the trace file, and printing final statistics.
     */
     
     

        // Set simulation mode (can be set based on command-line arguments)
       //  NormalMode = 1; // Set to normal mode; change to 0 for silent mode
       

//Read Trace File
logic [3:0] n;
logic [ADDRESS_WIDTH-1:0] address;
string filename;
string input_name;

trace_file_reader reader_instance (.n(n), .address(address));

initial begin
initialize_cache();
if (!$value$plusargs("mode=%d", NormalMode)) begin
            // Default to normal mode if not specified
            NormalMode = 1;
        end
if ($value$plusargs("filename=%s",filename))begin
input_name = filename;
end else begin
input_name = "//thoth.cecs.pdx.edu//Home05//bhavanas//Desktop//MSD_Checkpoint1//default.din";
end
   
   

    // Check if runtime debugging is enabled
   /* if ($value$plusargs("debug=%b", debug_enabled)) begin
        $display("Runtime debugging is enabled.");
    end else begin
        debug_enabled = 0;
    end */

    reader_instance.read_and_parse_file(input_name);  // Pass the variable name
     
     print_cache_contents();
end
endmodule
