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