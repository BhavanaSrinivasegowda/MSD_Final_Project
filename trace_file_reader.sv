module trace_file_reader(output reg [3:0] n, reg [31:0] address);
    `define DEBUG_ENABLED

    // Task to read and parse a file given the file name or path
    task read_and_parse_file(input string file_name);
        integer file;
        //logic [3:0] n1;
        //logic [31:0] address1;
        string line;
        //reg signed [3:0] n;      // Signed integer for parsing
        //reg signed [31:0] address; // Address parsed from the file

        // Open the file with the given name or path
        file = $fopen(file_name, "r");
        if (file == 0) begin
            $fatal("Error: Unable to open file '%s'", file_name);
        end else begin
            $display("Successfully opened file '%s'.", file_name);
        end

        // Read lines from the file
        while (!$feof(file)) begin
            // Correctly read a line into 'line'
            if ($fgets(line, file) != 0) begin
                `ifdef DEBUG_ENABLED
                $display("Read line: '%s'", line);
                // Parse the values from the line
                if ($sscanf(line, "%d %h", n, address) == 2) begin
                    $display("Parsed values: n:%d, address:%h", n, address);
                    
                     case(n) 
                4'd0: begin $display("read Request L1 data chache");
                      process_read_request_L1_DataCache(address);
                      end
                4'd1: process_write_request_data_cache(address);
                4'd2: read_request_from_L1_Instruction_cache(address);
                4'd3: Snooped_read_request(address);
                4'd4: Snooped_write_request(address);
                4'd5: Snooped_RWIM_request(address);
                4'd6: Snooped_invalidate_request(address);
                4'd8: clear_cache();
                4'd9: print_cache_contents();
                default: $display("no cases matched");
            endcase
                    
                end else begin
                    $display("Warning: Line format not as expected - '%s'", line);
                end
                `else 
                $display("Debug output disabled.");
                `endif
            end
        end

        // Close the file
        $fclose(file);
    endtask
endmodule
