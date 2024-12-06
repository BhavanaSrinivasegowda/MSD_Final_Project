//--------------------------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------------------------------


module cache_simulator;

   // Cache Parameters
   parameter ADDRESS_WIDTH = 32;                // Width of the memory addresses
   parameter CACHE_SIZE    = 16 * 1024 * 1024; // Total cache size in bytes (16MB)
   parameter LINE_SIZE     = 64;                // Size of each cache line in bytes
   parameter ASSOCIATIVITY = 16;                // Number of ways (16-way set associative)

   // Derived Parameters
   localparam NUM_LINES   = CACHE_SIZE / LINE_SIZE; // Total number of cache lines
   localparam NUM_SETS    = NUM_LINES / ASSOCIATIVITY; // Number of sets in the cache
   localparam OFFSET_BITS = $clog2(LINE_SIZE);         // Number of bits for offset within a cache line
   localparam INDEX_BITS  = $clog2(NUM_SETS);          // Number of bits for cache set index
   localparam TAG_BITS    = ADDRESS_WIDTH - INDEX_BITS - OFFSET_BITS; // Number of bits for tag

   // MESI Protocol States
   typedef enum logic [1:0] {
       INVALID   = 2'b00, // Invalid state
       SHARED    = 2'b01, // Shared state
       EXCLUSIVE = 2'b10, // Exclusive state
       MODIFIED  = 2'b11  // Modified state
   } MESI_State_t;

   // Cache Line Structure
   typedef struct packed {
       MESI_State_t          mesi_state;   // MESI state
       logic [TAG_BITS-1:0]  tag;          // Tag bits
   } CacheLine_t;

   // Cache Set Structure
   typedef struct {
       CacheLine_t lines [0:ASSOCIATIVITY-1];       // Array of cache lines in the set
   } CacheSet_t;

   // Cache Structure
   typedef struct {
       CacheSet_t sets [0:NUM_SETS-1];              // Array of cache sets
   } Cache_t;

   // Instantiate the cache
   Cache_t cache;

   // Cache Statistics Structure
   typedef struct {
       integer read_count;    // Number of cache read operations
       integer write_count;   // Number of cache write operations
       integer hit_count;     // Number of cache hits
       integer miss_count;    // Number of cache misses
   } CacheStats_t;

   CacheStats_t stats;

   // Initialize the cache
   initial begin
       initialize_cache();
   end

   // Cache initialization function
   task initialize_cache();
       integer set_index, line_index;
       begin
           for (set_index = 0; set_index < NUM_SETS; set_index++) begin
               for (line_index = 0; line_index < ASSOCIATIVITY; line_index++) begin
                   cache.sets[set_index].lines[line_index].mesi_state = INVALID; // Set all lines to INVALID
               end
           end
           stats.read_count  = 0;
           stats.write_count = 0;
           stats.hit_count   = 0;
           stats.miss_count  = 0;
       end
   endtask

   // Read request handling function
   task process_read_request(input logic [ADDRESS_WIDTH-1:0] address);
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
function void find_space(index)
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


// Function to get data from the bus
function int get_snoop_result_out(input logic [ADDRESS_WIDTH-1:0] address);
    case (address[1:0])
        2'b00: get_snoop_result = `HIT;   // ---00 = HIT
        2'b01: get_snoop_result = `HITM;  // ---01 = HITM
        default: get_snoop_result = `NOHIT; // ---10 or ---11 = NOHIT
    endcase
endfunction


// Function to read from DRAM
function logic [DATA_WIDTH-1:0] read_from_DRAM(input logic [ADDRESS_WIDTH-1:0] address);
    logic [DATA_WIDTH-1:0] data;

    // Simulate reading data from DRAM
    // In a real implementation, this would involve accessing the memory.
    // For simulation, we can just return some dummy data based on the address.
    data = address[DATA_WIDTH-1:0]; // Example: Just use the lower bits of the address as data

    $display("Reading from DRAM: Address = %h, Data = %h", address, data);
    return data;
endfunction

//this is the snoop result given by Xiang, i have just put a small code, since we will have to integrate, there will be all //functions present
// Bus operation simulation
task BusOperation(input int BusOp, input logic [ADDRESS_WIDTH-1:0] Address, input int SnoopResult);
    if (NormalMode) begin
        $display("BusOp: %s, Address: %h, Snoop Result: %s", bus_op_to_string(BusOp), Address,                  snoop_result_to_string(SnoopResult));
end
    endtask


    // Evict a cache line using LRU policy
    function integer evict_line(input logic [INDEX_BITS-1:0] index);
                if (current_set.lines[index].MESI.State_t == MODIFIED) begin
                //write to DRAM function 
                write_back_to_memory(index, empty_line);
                current_set.lines[empty_line].MESI.State_t = INVALIDATE;
                end
      endfunction


endmodule

------------------------------------------------------------------------------------------------------------------------------------------------------