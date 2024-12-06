//--------------------------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------------------------------------------------
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


endmodule

------------------------------------------------------------------------------------------------------------------------------------------------------
