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

Cache_t cache; // Instantiate cache

    // Function to find and evict a cache line using Pseudo LRU policy
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
