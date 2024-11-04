package trace_file_debug;

// Debugging function to display parsed line information
function void debug_line(string line, bit debug_enabled);
    // Use runtime flag to determine whether to print debug information
    `ifdef DEBUG_ENABLED
    initial begin
        $display("DEBUG (runtime): Parsed line: %s", line);
    end
   `else 
       $display("Output disabled due to conditional compilation.");   
   `endif
endfunction

endpackage

