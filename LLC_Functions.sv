/**
 * @file cache_simulator.sv
 * @brief Cache Simulator for ECE 485/585 Final Project
 *
 * This module simulates a last level cache (LLC) with MESI coherence protocol,
 * pseudo-LRU replacement policy, and supports bus operations and interactions
 * with higher-level caches.
 *
 * The cache is 16MB, 16-way set associative, with 64-byte lines.
 */

module cache_simulator;
// Data sructure for cache and inialization functions

    // Cache Parameters
    parameter ADDRESS_WIDTH = 32;                ///< Width of the memory addresses
    parameter CACHE_SIZE    = 16 * 1024 * 1024; ///< Total cache size in bytes (16MB)
    parameter LINE_SIZE     = 64;                ///< Size of each cache line in bytes
    parameter ASSOCIATIVITY = 16;                ///< Number of ways (16-way set associative)

    // Derived Parameters
    localparam NUM_LINES   = CACHE_SIZE / LINE_SIZE; ///< Total number of cache lines
    localparam NUM_SETS    = NUM_LINES / ASSOCIATIVITY; ///< Number of sets in the cache
    localparam OFFSET_BITS = $clog2(LINE_SIZE);         ///< Number of bits for offset within a cache line
    localparam INDEX_BITS  = $clog2(NUM_SETS);          ///< Number of bits for cache set index
    localparam TAG_BITS    = ADDRESS_WIDTH - INDEX_BITS - OFFSET_BITS; ///< Number of bits for tag

    // MESI Protocol States
    typedef enum logic [1:0] {
        INVALID   = 2'b00, ///< Invalid state
        SHARED    = 2'b01, ///< Shared state
        EXCLUSIVE = 2'b10, ///< Exclusive state
        MODIFIED  = 2'b11  ///< Modified state
    } MESI_State_t;

    // Cache Line Structure
    typedef struct packed {
    
    logic                 valid;        // Valid bit 
    logic [TAG_BITS-1:0]  tag;          // Tag bits 
    MESI_State_t          mesi_state;   // MESI state 

//    logic [INDEX_BITS-1:0] index;       // Set index
//    logic [OFFSET_BITS-1:0] offset;     // Byte Offset bits
//     Dupilcated, doesn't needed
    logic                 dirty;        // Dirty bit
    // No LRU bits at line level, use pseudo-LRU at set level
    } CacheLine_t;

    // Cache Set Structure
    typedef struct {
        CacheLine_t lines [0:ASSOCIATIVITY-1];       ///< Array of cache lines in the set
        logic [ASSOCIATIVITY-2:0] lru_state;         ///< Pseudo-LRU bits for replacement policy
    } CacheSet_t;

    // Cache Structure
    typedef struct {
        CacheSet_t sets [0:NUM_SETS-1];              ///< Array of cache sets
    } Cache_t;

    // Cache Statistics Structure
    typedef struct {
        integer read_count;    ///< Number of cache read operations
        integer write_count;   ///< Number of cache write operations
        integer hit_count;     ///< Number of cache hits
        integer miss_count;    ///< Number of cache misses
    } CacheStats_t;

    // Mode Control
    // logic NormalMode; ///< Simulation mode: 1 for normal mode, 0 for silent mode

    // Global Variables
    Cache_t cache;      ///< The cache instance
    CacheStats_t stats; ///< Cache statistics

    /** initialize_cache()
     * @brief Initializes the cache by setting all lines to invalid and resetting statistics.
     */
    // Iterate over all cache sets
    // Initialize pseudo-LRU bits for the set
    // Iterate over all cache lines in the set
    // Reset cache statistics
    task initialize_cache();
    endtask

    /** clear_cache()
     * @brief Clears the cache and resets all state.
     */
    task clear_cache();
        begin
            initialize_cache();
        end
    endtask

    /**print_cache_contents();
     * @brief Prints the contents and state of each valid cache line.
     */
    task print_cache_contents();
    endtask

//Cache Access Functions
    /**process_read_request_data_cache();
     * @brief Processes a read request from the L1 data cache.
     * @param address The memory address to read.
     *
     * This function handles read requests, checks for cache hits or misses,
     * updates the MESI state, and performs necessary bus operations if required.
     */

    function integer get_lru_line_index(input logic [ASSOCIATIVITY-2:0] lru_state);
    integer i;
    for (i = 0; i < ASSOCIATIVITY; i++) begin
        if (lru_state[i] == 0) begin
            return i; // Return the index of the least recently used line
        end
    end
    return -1; // If all lines are equally recently used, return -1 or some default value
    endfunction
    
    task process_read_request_data_cache(input logic [ADDRESS_WIDTH-1:0] address);
    // Extract the index, tag, and offset from the address
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;

    tag = address[ADDRESS_WIDTH-1:ADDRESS_WIDTH-TAG_BITS];
    index = address[OFFSET_BITS+TAG_BITS-1:OFFSET_BITS];
    offset = address[OFFSET_BITS-1:0];

    // Access the set corresponding to the index
    CacheSet_t current_set = cache.sets[index];

    // Initialize a flag to detect if the data was found (hit)
    logic hit = 0;
    integer i;
    
    // Search for the tag in the set's lines (associative lookup)
    for (i = 0; i < ASSOCIATIVITY; i++) begin
        if (current_set.lines[i].valid && current_set.lines[i].tag == tag) begin
            // Cache hit: Update the statistics and return
            hit = 1;
            cache_stats.read_count++;
            cache_stats.hit_count++;
            // You can also update the LRU state here, depending on the cache's design
            break;
        end
    end

    if (!hit) begin
        // Cache miss: Update the miss count and handle the miss (fetch from memory)
        cache_stats.read_count++;
        cache_stats.miss_count++;

        integer replacement_index = get_lru_line_index(current_set.lru_state);
        current_set.lines[replacement_index].valid = 1;
        current_set.lines[replacement_index].tag = tag;
        current_set.lines[replacement_index].mesi_state = EXCLUSIVE; // Initial state
        current_set.lines[replacement_index].dirty = 0; // Assuming it's not dirty yet

        // Update the LRU state as part of the replacement (if you are tracking LRU)
        update_lru_on_access(current_set.lru_state, replacement_index);
    end
endtask

    /**process_write_request_data_cache();
     * @brief Processes a write request from the L1 data cache.
     * @param address The memory address to write.
     *
     * This function handles write requests, checks for cache hits or misses,
     * updates the MESI state, and performs necessary bus operations if required.
     */
        // Code your design here
import cache_defs::*;
task process_write_request_data_cache(input logic [ADDRESS_WIDTH-1:0] address)

    tag = address[ADDRESS_WIDTH-1:ADDRESS_WIDTH-TAG_BITS];
    index = address[OFFSET_BITS+TAG_BITS-1:OFFSET_BITS];
    offset = address[OFFSET_BITS-1:0];
  
  stats.write_count ++;
  
  CacheSet_t current_set = cache.sets[index];
  logic hit = 0;
  integer i;

    // Search for the tag in the set's lines (associative lookup)
    for (i = 0; i < ASSOCIATIVITY; i++) begin
      logic way = i;
        if (current_set.lines[i].tag == tag) begin
            // Cache hit: Update the statistics and return
            hit = 1;
            stats.hit_count ++;
          case (current_set.lines[i].MESI_State_t)
            SHARED: begin 
              current_set.lines[i].mesi_state = MODIFIED;
              update_lru_on_access(index,way);
              // Call bus invalidate function.
                Busoperation(`INVALIDATE,address,`HIT);
            end
            MODIFIED : begin 
               current_set.lines[i].mesi_state = MODIFIED;
              update_lru_on_access(index, way);
            end
            EXCLUSIVE : begin
              current_set.lines[i].mesi_state = MODIFIED;
              update_lru_on_access(index, way);
            end
              endcase
          return;        
       end
            else begin
                   
              stats.miss_count ++;
              // call bus operation RWIM
                Busoperation(`RWIM,address,`NOHIT);
                for (int j=0;j<ASSOCIATIVITY;j++)
                 begin
                     if (current_set.lines[j].MESI_State_t == INVALIDATE)begin
                      logic empty_line = j;
                         current_set.lines[j].MESI_State_t = MODIFIED;
                         current_set.lines[j].tag = tag; 
                         messageToCache(`SENDLINE,address);
                    break;
                   else begin
                      logic [INDEX_BITS-1:0] z = select_victim_line(index);
                       logic evicted_line = evict_line(z);
                       current_set.lines[z].tag = tag; 
                       messageToCache(`EVICTLINE,address);
en
              // call bus operation sendline L1 
                
            end         ;
endtask

    /**rocess_read_request_instruction_cache();
     * @brief Processes a read request from the L1 instruction cache.
     * @param address The memory address to read.
     *
     * This function handles read requests from the instruction cache,
     * which can be processed similarly to data cache reads.
     */
    task process_read_request_instruction_cache(input logic [ADDRESS_WIDTH-1:0] address);

    endtask

    // Pseudo-LRU Replacement Policy Functions

    /**integer select_victim_line()
     * @brief Selects a cache line to replace using the pseudo-LRU policy.
     * @param index The cache set index.
     * @return The index of the way to replace within the set.
     *
     * This function implements a tree-based pseudo-LRU algorithm to select
     * a victim cache line for replacement.
     */
    function integer select_victim_line(input logic [INDEX_BITS-1:0] index);
    endfunction

    /**update_lru_on_access()
     * @brief Updates the pseudo-LRU bits after a cache access.
     * @param index The cache set index.
     * @param accessed_way The way (cache line) that was accessed.
     *
     * This function updates the LRU bits to reflect the recently accessed line,
     * ensuring that the replacement policy functions correctly.
     */
    task update_lru_on_access(input logic [INDEX_BITS-1:0] index, input integer accessed_way);
    endtask

    // MESI State Update Functions

    /**update_mesi_state_on_hit_read()
     * @brief Updates the MESI state on a read hit.
     * @param line_index The index of the cache line within the set.
     * @param index The cache set index.
     *
     * This function updates the MESI state of a cache line when a read hit occurs.
     */
    task update_mesi_state_on_hit_read(integer line_index, logic [INDEX_BITS-1:0] index);
    endtask

    /**update_mesi_state_on_hit_write()
     * @brief Updates the MESI state on a write hit.
     * @param line_index The index of the cache line within the set.
     * @param index The cache set index.
     * @param address The memory address being written.
     *
     * This function updates the MESI state of a cache line when a write hit occurs.
     */
    task update_mesi_state_on_hit_write(integer line_index, logic [INDEX_BITS-1:0] index, logic [ADDRESS_WIDTH-1:0] address);
    endtask

//Bus Operations and MESI Protocol Handling
    // Bus Operation Types (need modification)
    `define READ          1 ///< Bus Read
    `define WRITE         2 ///< Bus Write
    `define INVALIDATE    3 ///< Bus Invalidate
    `define RWIM          4 ///< Bus Read With Intent to Modify

    // Snoop Result Types
    `define NOHIT         0 ///< No Hit
    `define HIT           1 ///< Hit
    `define HITM          2 ///< Hit to Modified Line

    // Message Types to Higher-Level Cache
    `define GETLINE          1 ///< Request data for modified line in L1
    `define SENDLINE         2 ///< Send requested cache line to L1
    `define INVALIDATELINE   3 ///< Invalidate a line in L1
    `define EVICTLINE        4 ///< Evict a line from L1

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
    endtask

    /**process_snooped_bus_operation()
     * @brief Processes snooped bus operations from other processors.
     * @param opcode The operation code indicating the type of snooped operation.
     * @param address The memory address involved in the snooped operation.
     *
     * This function updates the MESI state of cache lines in response to snooped bus operations.
     */
    task process_snooped_bus_operation(input int opcode, input logic [ADDRESS_WIDTH-1:0] address);
    endtask

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






    
