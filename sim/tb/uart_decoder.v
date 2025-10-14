module uart_decoder 
  #(parameter BAUD_RATE = 115_200) 
   (input rx); 
   localparam T = 1000000000/BAUD_RATE; 
   integer i; 
   reg [7:0] ch; 
   initial forever 
        begin 
      @(negedge rx); 
      #(T/2) ch = 0; 
      for (i=0;i<8;i=i+1) 
                #T ch[i] = rx; 
     // $display("%c",ch); 
      $display("UART RX: %c (0x%02h)", ch, ch);

   end 

endmodule 
