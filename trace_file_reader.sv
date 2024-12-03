module trace_file_reader;
    `define DEBUG_ENABLED

    // Task to read and parse a file given the file name or path
    task read_and_parse_file(input string file_name);
        integer file;
        string line;
        reg signed [31:0] n;      // Signed integer for parsing
        reg signed [31:0] address; // Address parsed from the file

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
