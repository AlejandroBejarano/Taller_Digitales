module firstAnswerEncoder(
    input  logic no_answer,
    input  logic playerA_first,
    input  logic playerB_first,
    input  logic both_first,
    output logic responseP1,
    output logic responseP2
);

    always_comb begin
        // default
        responseP1 = 0;
        responseP2 = 0;

        if (both_first) begin
            responseP1 = 1;
            responseP2 = 1;
        end else if (playerA_first || playerB_first) begin
            responseP1 = 1;
        end
        // no_answer → both stay 0
    end


    //CAMBIO: se elimino el bloque always_ff @(posedge rst_i) porque carece de
    //clock y no es sintetizable (Vivado no puede inferir un flip-flop sin senal
    //de reloj). Ademas generaba multiples drivers de responseP1/responseP2 junto
    //con el always_comb de arriba. El reset entre rondas es automatico: como
    //firstAnswerEncoder es combinacional puro, cuando turnDecider resetea
    //playerA_first/playerB_first/both_first al inicio de una nueva ronda,
    //las salidas vuelven a 0 sin necesidad de logica de reset adicional.


endmodule