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
        if ((cache_reads + cache_writes) > 0) begin
            hit_ratio = (cache_hits * 100.0) / (cache_reads + cache_writes);
        end else begin
            hit_ratio = 0.0;
        end
        // Print cache statistics
        $display("\nCache Statistics:");
        $display("Number of cache reads: %0d", cache_reads);
        $display("Number of cache writes: %0d", cache_writes);
        $display("Number of cache hits: %0d", cache_hits);
        $display("Number of cache misses: %0d", cache_misses);
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
// Seacrh for the line in the cache, if it exixts in E,S state, invilidate it and send messgae to L1
// If it is in M state, do Bus write, and Getline and Invalidate to L1
task Snooped_RWIM_request(input logic [ADDRESS_WIDTH-1:0] address);
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
                    cache.sets[index].lines[line_index].mesi_state = `INVALID;
                    messageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                ELSE IF (cache.sets[index].lines[line_index].mesi_state == `SHARED) begin
                    cache.sets[index].lines[line_index].mesi_state = `INVALID;
                    messageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                ELSE IF (cache.sets[index].lines[line_index].mesi_state == `MODIFIED) begin
                    BusOperation(`WRITE, address, `RWIM);
                    messageToCache(`GETLINE, address);
                    messageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HITM);
                end
                ELSE begin
                    PutSnoopResult(address,`NOHIT);
                end
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
                IF (cache.sets[index].lines[line_index].mesi_state == `EXCLUSIVE) begin
                    cache.sets[index].lines[line_index].mesi_state = `INVALID;
                    messageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                ELSE IF (cache.sets[index].lines[line_index].mesi_state == `SHARED) begin
                    cache.sets[index].lines[line_index].mesi_state = `INVALID;
                    messageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HIT);
                end
                ELSE IF (cache.sets[index].lines[line_index].mesi_state == `MODIFIED) begin
                    cache.sets[index].lines[line_index].mesi_state = `INVALID;
                    messageToCache(`INVALIDATELINE, address);
                    PutSnoopResult(address, `HITM);
                end
                ELSE begin
                    PutSnoopResult(address, `NOHIT);
                end
            end
        end
    end
endtask

function integer select_victim_line(input logic [INDEX_BITS-1:0] set_index);
    CacheSet_t cache_set;
    int evict_index;
    int level;

    // Get the specified cache set
    cache_set = cache.sets[set_index];

    // Traverse the pseudo LRU tree to find the line to evict
    for (level = 0; level < $clog2(ASSOCIATIVITY); level++) begin
        // Ensure that we do not exceed the bounds of lru_state
        if (evict_index >= ASSOCIATIVITY - 1) begin
            // This should not happen, but just in case, return an invalid index
            return -1; // Indicate an error
        end

        // Move left or right based on the current state of lru_state
        if (cache_set.lru_state[evict_index] == 0) begin
            evict_index = (evict_index << 1); // Go left
        end else begin
            evict_index = (evict_index << 1) | 1; // Go right
        end
    end

    // Ensure evict_index is within valid range
    if (evict_index >= ASSOCIATIVITY) begin
        return -1; // Indicate an error
    end

    // Return the index of the cache line to evict
    return evict_index;
endfunction


    // Function to update the pseudo LRU bits after accessing a cache line
    task update_lru_on_access(input logic [INDEX_BITS-1:0] set_index, input integer accessed_index);
    CacheSet_t cache_set;
    int i;

    // Get the specified cache set
    cache_set = cache.sets[set_index];

    // Update the pseudo LRU bits
    // Reset all bits
    for (i = 0; i < ASSOCIATIVITY - 1; i++) begin
        cache_set.lru_state[i] = 0; // Reset all bits first
    end

    // Set the accessed line as most recently used
    for (i = 0; i < $clog2(ASSOCIATIVITY); i++) begin
        if (accessed_index & (1 << i)) begin
            cache_set.lru_state[(1 << i) - 1] = 1; // Mark the path to the accessed line
        end else begin
            cache_set.lru_state[(1 << i) - 1] = 0; // Reset paths not leading to accessed line
        end
    end

    // Update the cache set's LRU state
    cache.sets[set_index] = cache_set;
endtask

   task process_read_request_L1_DataCache(input logic [ADDRESS_WIDTH-1:0] address);
       logic [TAG_BITS-1:0] tag;
       logic [INDEX_BITS-1:0] index;
       integer line_index;
       logic hit;

       // Decode the address
       decode_address(address, tag, index);

       // Access the corresponding cache set
       CacheSet_t current_set = cache.sets[index];

       // Initialize hit flag
       hit = 0;

       // Search for the tag in the set's lines
       for (line_index = 0; line_index < ASSOCIATIVITY; line_index++) begin
           if (current_set.lines[line_index].mesi_state != INVALID && 
               current_set.lines[line_index].tag == tag) begin
               // Cache hit
               hit = 1;
               stats.read_count++;
               stats.hit_count++;
               // MESI state remains the same
               //update PLRU
                update_lru_on_access(current_set.lru_state, i);
               break;
           end
       end

       if (!hit) begin
           // Cache miss
           stats.read_count++;
           stats.miss_count++;

           // Perform BusRd and snoop the bus
           int snoop_result;
           BusOperation(`READ, address, snoop_result);

           if (snoop_result == `HIT) begin
               // Get data from bus
               get_snoop_result_out(address);
               line_index = find_space();
               // Change state to SHARED
               current_set.lines[line_index].mesi_state = SHARED;
               MessageToCache(`SENDLINE, address);
           end else if (snoop_result == `HITM) begin
               // Get data from bus
               get_snoop_result_out(address);
                line_index = find_space();
               // Change state to SHARED
               current_set.lines[line_index].mesi_state = SHARED;
               MessageToCache(`SENDLINE, address);
           end else if (snoop_result == `NOHIT) begin
               // Read from DRAM
               read_from_DRAM(address);
               line_index = find_space();
               // Change state to EXCLUSIVE
               current_set.lines[line_index].mesi_state = EXCLUSIVE;
               MessageToCache(`SENDLINE, address);
           end
       end
   endtask
//--------------------------------------------------------------------------------------------------------------------------------------------------
  
// findspace 
function find_space(index)
for (int i=0;i<ASSOCIATIVITY;i++)
begin
if (current_set.lines[i].MESI_State_t == INVALIDATE)begin
logic empty_line = i;
return empty_line;
break;
else begin
logic [INDEX_BITS-1:0] z = select_victim_line(index);
logic evicted_line = evict_line(z);
return evicted_line;
end


 
function integer select_victim_line(input logic [INDEX_BITS-1:0] index);
    // Access the current set
    CacheSet_t current_set = cache.sets[index];

    // Use LRU policy to select the victim line
    return get_lru_line_index(current_set.lru_state);
endfunction



task write_back_to_memory(input logic [INDEX_BITS-1:0] index, input CacheLine_t line);
    // Check if the line is modified
    if (current_set.lines[line_index].mesi_state == MODIFIED ) begin
        // Combine the tag, index, and offset to form the memory address
        logic [ADDRESS_WIDTH-1:0] address;
        address = {line.tag, index, {OFFSET_BITS{1'b0}}}; // Address points to the start of the line

        // Simulate memory write-back
        $display("Write-back to memory: Address = %h, Data = <line data here>", address);
    end
endtask

  // Function to return data to L1
function void return_data_to_L1(input logic [ADDRESS_WIDTH-1:0] address, input logic [DATA_WIDTH-1:0] data);
    // Here, you would typically send the data back to the L1 cache.
    // For simulation purposes, we can just print the address and data.
    $display("Returning data to L1: Address = %h, Data = %h", address, data);
endfunction


// Function to read from DRAM
function read_from_DRAM(input logic [ADDRESS_WIDTH-1:0] address);
    $display("Reading from DRAM: Address = %h", address);
endfunction

    // Evict a cache line using LRU policy
    function integer evict_line(input logic [INDEX_BITS-1:0] index);
                if (current_set.lines[index].MESI.State_t == MODIFIED) begin
                //write to DRAM function 
                write_back_to_memory(index, empty_line);
                current_set.lines[empty_line].MESI.State_t = INVALIDATE;
                end
      endfunction

    function read_request_from_L1_Instruction_cache(input logic [ADDRESS_WIDTH -1 :0] address);
        process_read_request_L1_DataCache(address);
    endfunction
//Simulation Control and Trace File Processing
    /**
     * @brief Processes the trace file containing memory operations.
     * @param filename The name of the trace file to process.
     *
     * This function reads memory operations from the trace file and dispatches them
     * to the appropriate handlers.
     */

    // Instantiate the trace_file_reader module statically
    trace_file_reader reader_instance();
    // Task to process the trace file
    task process_trace_file(input string filename);
        begin
            $display("Processing trace file: '%s'", filename);

            // Call the read_and_parse_file task using the static instance
            reader_instance.read_and_parse_file(filename);
        end
     endtask
    // Example usage of the process_trace_file task
    initial begin
        string filename, input_name;
        if ($value$plusargs("filename=%s", filename)) begin
            input_name = filename;
        end else begin
            input_name = "//thoth.cecs.pdx.edu//Home05//bhavanas//Desktop//MSD_Checkpoint1//default.din";
        end

        // Call the process_trace_file task
        process_trace_file(input_name);
    end


    /**
     * @brief Main simulation control.
     *
     * This initial block coordinates the overall simulation, including initialization,
     * processing the trace file, and printing final statistics.
     */
    initial begin
        // Set simulation mode (can be set based on command-line arguments)
        NormalMode = 1; // Set to normal mode; change to 0 for silent mode

        // Initialize the cache
        initialize_cache();

        // Process the trace file
        process_trace_file("trace.txt"); // Replace "trace.txt" with the actual trace file name

        // Print final cache statistics
        $display("Cache Statistics:");
        $display("Number of cache reads: %0d", stats.read_count);
        $display("Number of cache writes: %0d", stats.write_count);
        $display("Number of cache hits: %0d", stats.hit_count);
        $display("Number of cache misses: %0d", stats.miss_count);
        $display("Cache hit ratio: %f", (stats.hit_count * 1.0) / (stats.read_count + stats.write_count));

        $finish;
    end

endmodule

