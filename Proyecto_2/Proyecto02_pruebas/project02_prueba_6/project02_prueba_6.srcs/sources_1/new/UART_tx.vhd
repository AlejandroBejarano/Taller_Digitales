library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART_tx is
    generic(
        BAUD_CLK_TICKS: integer := 139  -- 16 MHz / 115200 = 138.89 ..............139...................
    );
    port(
        clk            : in  std_logic;
        reset          : in  std_logic;
        tx_start       : in  std_logic;
        tx_rdy         : out std_logic;
        tx_data_in     : in  std_logic_vector (7 downto 0);
        tx_data_out    : out std_logic
    );
end UART_tx;

architecture Behavioral of UART_tx is
    type tx_states_t is (IDLE, START, DATA, STOP);
    signal tx_state  : tx_states_t := IDLE;
    signal baud_rate_clk     : std_logic:= '0';
    signal data_index        : integer range 0 to 7 := 0;
    signal data_index_reset  : std_logic := '1';
    signal stored_data       : std_logic_vector(7 downto 0) := (others=>'0');
    signal start_detected    : std_logic := '0';
    signal start_reset       : std_logic := '0';
    signal tx_end            : std_logic := '0';
    signal edge_signal       : std_logic := '0';
begin

    baud_rate_clk_generator: process(clk)
        variable baud_count: integer range 0 to (BAUD_CLK_TICKS - 1) := (BAUD_CLK_TICKS - 1);
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                baud_rate_clk <= '0';
                baud_count := (BAUD_CLK_TICKS - 1);
            else
                if (baud_count = 0) then
                    baud_rate_clk <= '1';
                    baud_count := (BAUD_CLK_TICKS - 1);
                else
                    baud_rate_clk <= '0';
                    baud_count := baud_count - 1;
                end if;
            end if;
        end if;
    end process;

    tx_start_detector: process(clk)
    begin
        if rising_edge(clk) then
            if (reset ='1') or (start_reset = '1') then
                start_detected <= '0';
            else
                if (tx_start = '1') and (start_detected = '0') then
                    start_detected <= '1';
                    stored_data <= tx_data_in;
                end if;
            end if;
        end if;
    end process;

    data_index_counter: process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') or (data_index_reset = '1') then
                data_index <= 0;
            elsif (baud_rate_clk = '1') then
                data_index <= data_index + 1;
            end if;
        end if;
    end process;

    UART_tx_FSM: process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                tx_state <= IDLE;
                data_index_reset <= '1';
                start_reset <= '1';
                tx_data_out <= '1';
                tx_end      <= '0';
            else
                if (baud_rate_clk = '1') then
                    case tx_state is
                        when IDLE =>
                            tx_end           <= '0';
                            data_index_reset <= '1';
                            start_reset <= '0';
                            tx_data_out <= '1';
                            if (start_detected = '1') then
                                tx_state <= START;
                            end if;
                        when START =>
                            tx_end           <= '0';
                            data_index_reset <= '0';
                            tx_data_out <= '0';
                            tx_state <= DATA;
                        when DATA =>
                            tx_data_out <= stored_data(data_index);
                            if (data_index = 7) then
                                data_index_reset <= '1';
                                tx_state <= STOP;
                            end if;
                        when STOP =>
                            tx_data_out <= '1';
                            start_reset <= '1';
                            tx_end      <= '1';
                            tx_state <= IDLE;
                        when others =>
                            tx_end      <= '0';
                            tx_state    <= IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;

    TX_RDY_P : process(clk)
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                tx_rdy      <= '0'; 
                edge_signal <= '0';
            else
                tx_rdy      <= tx_end and (not edge_signal);
                edge_signal <= tx_end;
            end if;
         end if;
    end process;
      
end Behavioral;