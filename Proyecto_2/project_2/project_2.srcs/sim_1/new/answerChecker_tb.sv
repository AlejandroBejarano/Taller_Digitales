`timescale 1ns/1ps

module tb_answer_checker;

    // DUT signals
    logic clk;
    logic rst;
    logic [3:0] question_index;
    logic [1:0] answer_p1;
    logic [1:0] answer_p2;
    logic tA, tB;

    logic responseP1;
    logic responseP2;

    // Instantiate DUT
    answer_checker dut (
        .clk(clk),
        .rst(rst),
        .question_index(question_index),
        .answer_p1(answer_p1),
        .answer_p2(answer_p2),
        .tA(tA),
        .tB(tB),
        .responseP1(responseP1),
        .responseP2(responseP2)
    );

    // Clock (10 ns period)
    always #5 clk = ~clk;

    initial begin
        // Initial values
        clk = 0;
        rst = 1;
        tA = 0;
        tB = 0;
        question_index = 0;
        answer_p1 = 0;
        answer_p2 = 0;

        #10;
        rst = 0;

        // =========================
        // TEST 1: Q0 = C (10)
        // =========================
        question_index = 4'd0;
        answer_p1 = 2'b10; // correct
        answer_p2 = 2'b00; // wrong
        tA = 1;
        tB = 1;

        #10;
        $display("TEST1 -> respP1=%b respP2=%b", responseP1, responseP2);

        // =========================
        // TEST 2: Q1 = A (00)
        // =========================
        question_index = 4'd1;
        answer_p1 = 2'b00; // correct
        answer_p2 = 2'b00; // correct
        tA = 1;
        tB = 1;

        #10;
        $display("TEST2 -> respP1=%b respP2=%b", responseP1, responseP2);

        // =========================
        // TEST 3: Q2 = D (11)
        // =========================
        question_index = 4'd2;
        answer_p1 = 2'b01; // wrong
        answer_p2 = 2'b11; // correct
        tA = 1;
        tB = 1;

        #10;
        $display("TEST3 -> respP1=%b respP2=%b", responseP1, responseP2);

        // =========================
        // TEST 4: Only P1 updates
        // =========================
        question_index = 4'd3; // correct = D
        answer_p1 = 2'b11; // correct
        answer_p2 = 2'b00; // wrong
        tA = 1;
        tB = 0;

        #10;
        $display("TEST4 -> respP1=%b respP2=%b (P2 should HOLD)", responseP1, responseP2);

        // =========================
        // TEST 5: Only P2 updates
        // =========================
        question_index = 4'd3;
        answer_p1 = 2'b00; // wrong
        answer_p2 = 2'b11; // correct
        tA = 0;
        tB = 1;

        #10;
        $display("TEST5 -> respP1=%b respP2=%b (P1 should HOLD)", responseP1, responseP2);

        // =========================
        // TEST 6: No trigger → hold both
        // =========================
        question_index = 4'd4;
        answer_p1 = 2'b01;
        answer_p2 = 2'b01;
        tA = 0;
        tB = 0;

        #10;
        $display("TEST6 -> respP1=%b respP2=%b (both HOLD)", responseP1, responseP2);

        #20;
        $finish;
    end

endmodule