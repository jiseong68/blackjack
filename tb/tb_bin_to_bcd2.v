`timescale 1ns/1ps

module tb_bin_to_bcd2;
    reg  [4:0] bin;
    wire [3:0] tens, ones;
    integer i, errors;

    bin_to_bcd2 dut(.bin(bin), .tens(tens), .ones(ones));

    initial begin
        errors = 0;
        for (i = 0; i < 32; i = i + 1) begin
            bin = i[4:0];
            #10;
            if (tens !== (i / 10) || ones !== (i % 10)) begin
                errors = errors + 1;
                $display("FAIL bin=%0d tens=%0d ones=%0d", i, tens, ones);
            end
        end
        if (errors == 0) $display("PASS tb_bin_to_bcd2: all 32 values OK");
        else             $display("FAIL tb_bin_to_bcd2: %0d errors", errors);
        $finish;
    end
endmodule