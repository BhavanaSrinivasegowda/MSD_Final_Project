// Cache Simulation Data Structures for ECE 585 Final Project
// Version: 0.2
// Cache Parameters
parameter ADDRESS_WIDTH = 32; // Address width 
parameter CACHE_SIZE    = 16 * 1024 * 1024; // 16MB cache size , all in BYTEs
parameter LINE_SIZE     = 64; // Cache line size 64 Bytes 
parameter ASSOCIATIVITY = 16; // 16-way set associative 

localparam NUM_LINES  = CACHE_SIZE / LINE_SIZE; // Total number of lines, in this case 256K lines
localparam NUM_SETS   = NUM_LINES / ASSOCIATIVITY; // Number of sets, in this case 16K sets
localparam OFFSET_BITS = $clog2(LINE_SIZE); // Offset bits , in this case 6 bits
localparam INDEX_BITS  = $clog2(NUM_SETS); // Index bits , in this case 14 bits
localparam TAG_BITS    = ADDRESS_WIDTH - INDEX_BITS - OFFSET_BITS; // Tag bits , in this case 12 bits, total 32 bits

// MESI State Enumeration
// Show all possible MESI states
typedef enum logic [1:0] {
    INVALID   = 2'b00, // Invalid 
    SHARED    = 2'b01, // Shared 
    EXCLUSIVE = 2'b10, // Exclusive 
    MODIFIED  = 2'b11  // Modified 
} MESI_State_t;

// Cache Line Structure
// 
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
    CacheLine_t lines [0:ASSOCIATIVITY-1];      // Array of cache lines 
    logic [ASSOCIATIVITY-2:0] lru_state;        // Pseudo-LRU bits: in this case 15 bits
} CacheSet_t;

// Cache Structure
// 
typedef struct {
    CacheSet_t sets [0:NUM_SETS-1]; // Array of cache sets , in this case 16K sets
} Cache_t;

// Cache Statistics Structure
// 
typedef struct {
    integer read_count;   // Number of cache reads 
    integer write_count;  // Number of cache writes 
    integer hit_count;    // Number of cache hits 
    integer miss_count;   // Number of cache misses 
} CacheStats_t;

// Here are some possible sturctures that I'm not sure if needed
// Bus Operations Structures
// 
// Functions
// 
// Communication Structures with Higher-Level Cache
// 

