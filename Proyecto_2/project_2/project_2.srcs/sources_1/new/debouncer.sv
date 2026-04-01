`timescale 1ns / 1ps

module debouncer (
    input wire clk,
    input wire reset,
    input wire btn_in,
    output reg btn_out
);

    // Parámetro para 10ms a 100MHz (1,000,000 de ciclos)
    // Para simulación rápida, puedes bajarlo a 20.
    parameter COUNT_MAX = 20; //normal a 1000000

    reg [19:0] counter = 0;
    reg btn_sync_0, btn_sync_1;

    // Sincronizador de 2 etapas para evitar metaestabilidad
    always @(posedge clk) begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end

    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            btn_out <= 0;
        end else begin
            // Si el estado del botón sincronizado es distinto a la salida actual
            if (btn_sync_1 != btn_out) begin
                if (counter >= COUNT_MAX) begin
                    counter <= 0;
                    btn_out <= btn_sync_1; // El estado es estable, actualizamos
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                counter <= 0; // Si el botón regresa a su estado anterior, reseteamos contador
            end
        end
    end
endmodule