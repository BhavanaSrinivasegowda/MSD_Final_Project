module trace_file_reader;

import trace_file_debug::*;

// Task to read and parse a file given the file name or path
task read_and_parse_file(input string file_name = "default.din");
    integer file;
    string line;
    string str_value1;
    reg signed [31:0] n; // Declare value1 as a signed integer
    reg signed [31:0] address; // value2 remains a string

    // Open the file with the given name or path
    file = $fopen(file_name, "r");
    if (file == 0) begin
        $fatal("Error: Unable to open file '%s'", file_name);
    end else begin
        $display("Successfully opened file '%s'.", file_name);
    end

    // Read and parse lines from the file
    while (!$feof(file)) begin
        // Correctly read a line into 'line'
        if ($fgets(line, file) != 0) begin
            $display("Read line: '%s'", line);
            // Parse the values from the line
            if ($sscanf(line, "%d %h", n, address) == 2) begin
                $display("Parsed values: n:%d, address:%h", n, address);
            end else begin
                $display("Warning: Line format not as expected - '%s'", line);
            end
        end
    end

    // Close the file
    $fclose(file);
endtask


// Example call to the task
initial begin
    string input_name = "//thoth.cecs.pdx.edu//Home05//bhavanas//Desktop//MSD_Checkpoint1//rwims.din";  
    `define DEBUG_ENABLED;

    // Check if runtime debugging is enabled
   /* if ($value$plusargs("debug=%b", debug_enabled)) begin
        $display("Runtime debugging is enabled.");
    end else begin
        debug_enabled = 0;
    end */

    read_and_parse_file(input_name);  // Pass the variable name
end

endmodule

