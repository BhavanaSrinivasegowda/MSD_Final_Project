task process_read_request_data_cache(input logic [ADDRESS_WIDTH-1:0] address);
    // Variable declarations
    logic [TAG_BITS-1:0] tag;
    logic [INDEX_BITS-1:0] index;
    logic [OFFSET_BITS-1:0] offset;
    integer line_index;
    logic hit;
    logic [1:0] snoop_result;
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
            line_index = find_space(index);
            // Update the cache line
            cache.sets[index].lines[line_index].tag = tag;
            cache.sets[index].lines[line_index].mesi_state  = SHARED;
            cache.sets[index].lines[line_index].valid = 1;
            // Send message to the cache
            MessageToCache(`SENDLINE, address);
        end else if (snoop_result == `NOHIT) begin
            // Bus read operation
            BusOperation(`READ, address, `NOHIT);
            line_index = find_space(index);
            // Update the cache line
            cache.sets[index].lines[line_index].tag = tag;
            cache.sets[index].lines[line_index].mesi_state = EXCLUSIVE;
            cache.sets[index].lines[line_index].valid = 1;
            // Send message to the cache
            MessageToCache(`SENDLINE, address);
        end
        // Update the LRU state
        update_lru_on_access(index, line_index);
    end
endtask