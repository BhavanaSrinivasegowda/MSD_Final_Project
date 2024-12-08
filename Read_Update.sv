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
            line_index = find_space(index);
            // Update the cache line
            cache.sets[index].lines[line_index].tag = tag;
            cache.sets[index].lines[line_index].mesi_state  = SHARED;
            // Send message to the cache
            MessageToCache(`SENDLINE, address);
        end else if (snoop_result == `NOHIT) begin
            // Bus read operation
            BusOperation(`READ, address, `NOHIT);
            line_index = find_space(index);
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
        line_index = find_space(index);
        // Update the cache line
        cache.sets[index].lines[line_index].tag        = tag;
        cache.sets[index].lines[line_index].mesi_state = MODIFIED;

        // Update the LRU state
        update_lru_on_access(index, line_index);

        // Send message to the cache
        MessageToCache(`SENDLINE, address);
    end
endtask