module Bicubic (
input CLK,
input RST,
input [6:0] V0,
input [6:0] H0,
input [4:0] SW,
input [4:0] SH,
input [5:0] TW,
input [5:0] TH,
output reg DONE);

reg en16;
reg [15:0] cs,ns;
parameter IDLE = 0, INEN_s = 1, INEN_4p = 2, P = 3, BIC = 4, WAIT = 5, WAIT_2 = 6, BIC_2 = 7, OVER =8, 
            XSUM = 9,S1 = 10,XDIV = 11 , YSUM = 12 , YDIV = 13 ,WAIT_C = 14, WAIT_CC = 15;
reg [6:0] X_T,Y_T;//讀寫rom ram時的座標
reg [1:0] cnt_p,cnt_p16;//cnt_p計算拿取次數 cnt_p16計算做幾次BIC
reg [5:0] cnt_x,cnt_y;//cnt_x(x方向計數器) cnt_y(y方向計數器) 
reg inen,outen,overen; //讀出寫入rom ram 智能訊號
wire[13:0]addr_rom;//地址
wire[13:0]addr_ram;//地址
wire [7:0]Q_in;//讀入值
reg [7:0] C;//寫出值
reg signed[9:0] p0,p1,p2,p3,b1,b2,b3,b0;//1位小數
reg signed[9:0] P0,P1,P2,P3;//1位小數
wire signed[30:0] a,b,c,d;//1位小數

reg [14:0] x;  //15位小數
wire [29:0]x_2;//30位小數
wire [44:0]x_3;//45位小數

wire signed[45:0] x1;//45位小數
wire signed[45:0] x2;//45位小數
wire signed[45:0] x3;//45位小數

wire signed[150:0] Pxe;//+-_整數_46小數
reg [7:0] PA;

reg[13:0] x_sum , y_sum , x_rem , y_rem; //sum累加合 rem餘數
reg[6:0] xsum_c , ysum_c , xdiv_c , ydiv_c; //sum_c累加次數 div_c連減次數(商) 

reg[3:0] pin;//要求的點的落點(註解在65行開始)
parameter  lt = 4'd0, rt = 4'd1, ld = 4'd2, rd = 4'd3, ton = 4'd4, lon = 4'd5, ron = 4'd6, don = 4'd7, con = 4'd8, top = 4'd9, left = 4'd10, right = 4'd11, down = 4'd12, center = 4'd13;


//rom 位置
assign addr_rom = X_T + ( Y_T << 6 ) + ( Y_T << 5) + (Y_T << 2); //assign addr_rom = X_T + (Y_T*100);
ImgROM u_ImgROM (.Q(Q_in), .CLK(CLK), .CEN(inen), .A(addr_rom)); 

//如果取的點剛好在原圖點上 不須經過bicubic就可以直接寫入ram
always@(posedge CLK)begin
        if(RST) C <= 'd0;
        else if((pin == center) || (pin == top) || (pin == down) || (pin == right) || (pin == left))
            C <= PA; //計算後的值給到寫出值
        else if(cs[WAIT]) C <= Q_in; //讀入的值直接給到寫出值
end

//ram 位置
assign addr_ram = cnt_x + (cnt_y*TW); 
ResultSRAM u_ResultSRAM (.Q(), .CLK(CLK), .CEN(outen), .WEN(outen), .A(addr_ram), .D(C));

////////////////////////////////////////////////////////////cle///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


always @(*) begin
    if((~|cnt_x)&&(~|cnt_y )) //左上角
        pin = lt;
    else if((cnt_x == (TW - 6'd1))&&(~|cnt_y)) //右上角
        pin = rt;
    else if((~|cnt_x )&&(cnt_y == (TH - 6'd1))) //左下角
        pin = ld;
    else if((cnt_x == (TW - 6'd1))&&(cnt_y == (TH - 6'd1))) //右下角
        pin = rd;
    else if((~|x_rem) && (~|cnt_y)) //上邊點上
        pin = ton;
    else if((~|y_rem) && (~|cnt_x )) //左邊點上
        pin = lon;
    else if((~|y_rem) && (cnt_x == (TW - 6'd1))) //右邊點上
        pin = ron; 
    else if((~|x_rem) && (cnt_y == (TH - 6'd1))) //下邊點上
        pin = don;
    else if((~|x_rem) && (~|y_rem)) //中間點上
        pin = con;
    ///
    else if((~|cnt_y) )//上邊&& ((((SW-1)*cnt_x)%(TW-1))!=6'd0)
        pin = top;
    else if(~|cnt_x ) //左邊
        pin = left;
    else if(cnt_x == (TW - 6'd1)) //右邊
        pin = right;
    else if(cnt_y == (TH - 6'd1)) //下邊
        pin = down;
    ///
    else //中間
        pin = center;
end


always @(posedge CLK) begin
    if(RST)
        overen <= 1'd0;
    else if (cs[IDLE]) overen <= 1'd0;
    else overen <= 1'd1;
end

always @(posedge CLK) begin
    if(RST)begin
        cs <= 'd1;
    end
    else cs <= ns;
end

//狀態
always@(*)begin
    ns = 'd0;
    case (1'd1)
        cs[IDLE]:                                       ns[S1] = 1'd1;

        //判斷是否全部點都做過一遍 是的話進OVER
        cs[S1]: 
            if((~|cnt_x ) && (~|cnt_y ) && (overen ))   ns[OVER] = 1'd1; 
            else                                        ns[XSUM] = 1'd1; 

        //累加求x方向乘積
        cs[XSUM]:   if(xsum_c == cnt_x)                 ns[XDIV] = 1'd1; 
                    else                                ns[XSUM] = 1'd1;

        //連減求x方向商與餘數
        cs[XDIV]:   if(x_rem < (TW-1))                  ns[YSUM] = 1'd1; 
                    else                                ns[XDIV] = 1'd1;

        //累加求y方向乘積
        cs[YSUM]:   if(ysum_c == cnt_y)                 ns[YDIV] = 1'd1;
                    else                                ns[YSUM] = 1'd1;

        //連減求y方向商與餘數
        cs[YDIV]:   if(y_rem < (TH-1))begin 
                        if((pin==lt) || (pin==rt) || (pin==ld) || (pin==rd) || (pin==ton) || (pin==lon) || (pin==ron) || (pin==don) || (pin==con)) //水平垂直方向皆重合
                                                        ns[INEN_s] = 1'd1; //水平垂直方向皆重合
                        else                            ns[INEN_4p] = 1'd1; 
                    end 
                    else                                ns[YDIV] = 1'd1;

        //水平垂直方向皆重合 只需拿1筆資料
        cs[INEN_s]:                                     ns[WAIT] = 1'd1; 

        //垂直V方向或水平H方向重合 需要拿4筆資料
        cs[INEN_4p]:                                    ns[P] = 1'd1;
        cs[P]:  if(cnt_p == 2'd3)                       ns[BIC] = 1'd1; 
                else                                    ns[INEN_4p] = 1'd1; 

        //用4筆資料算單一方向(x or y)的bicubic 算完要經過2clk的等待
        cs[BIC]:                                        ns[WAIT] = 1'd1;

        cs[WAIT]:                                       ns[WAIT_C] = 1'd1;

        cs[WAIT_C]:begin
            if(pin==center)begin //需要算完4遍單一方向(x or y)的bicubic(cnt_p16==2'd3)，之後拿得到的值算一遍另一方向(y or x)的bicubic(BIC_2)(做完後en16==1'd1)
                if(en16)                                ns[WAIT_CC] = 1'd1; //做完所有BIC與BIC_2 將值存入RAM
                else begin
                    if(cnt_p16 == 2'd3)                 ns[WAIT_2] = 1'd1;  //做完4遍BIC要去做BIC_2
                        else                            ns[INEN_4p] = 1'd1;
                end
            end
            else                                        ns[S1] = 1'd1;
        end

        //1clk等待
        cs[WAIT_CC]:                                    ns[S1] = 1'd1;

        //1clk等待
        cs[WAIT_2]:                                     ns[BIC_2] = 1'd1; 

        //與BIC不同方向的bicubic
        cs[BIC_2]:                                      ns[WAIT] = 1'd1;

        cs[OVER]:                                       ns[IDLE] = 1'd1;

        default:                                        ns[IDLE] = 1'd1;
    endcase
end

///xsum
//x方向累加之和
always @(posedge CLK) begin
    if(RST)begin
        x_sum <= 14'd0;
    end
    else begin
        case (1'd1)
            ns[IDLE]:begin
                x_sum <= 14'd0;
            end
            ns[S1]:begin
                x_sum <= 14'd0;
            end
            ns[XSUM]:begin
                if(xsum_c == cnt_x)begin
                    x_sum <= x_sum;
                end
                else begin
                    x_sum <= x_sum + (SW-5'd1);
                end
            end 
            default:begin
                x_sum <= x_sum;
            end 
        endcase
    end
end
//x方向累加了幾次
always @(posedge CLK) begin
    if(RST)begin
        xsum_c <= 7'd0;
    end
    else begin
        case (1'd1)
            ns[IDLE]:begin
                xsum_c <= 7'd0;
            end
            ns[S1]:begin
                xsum_c <= 7'd0;
            end
            ns[XSUM]:begin
                if(xsum_c == cnt_x)begin
                    xsum_c <= xsum_c;
                end
                else begin
                    xsum_c <= xsum_c + 7'd1;
                end
            end 
            default:begin
                xsum_c <= xsum_c;
            end 
        endcase
    end
end

///x_rem
//x方向連減取後剩下的餘數
always @(posedge CLK) begin
    if(RST)begin
        x_rem <= 14'd0;
    end
    else begin
        case (1'd1)
            ns[IDLE]: x_rem <= 14'd0;
            ns[S1]: x_rem <= 14'd0;
            ns[XSUM]:begin
                if(xsum_c == cnt_x)
                    x_rem <= x_rem;
                else 
                    x_rem <= x_rem + (SW-5'd1);
            end
            ns[XDIV]:begin
                if(x_rem<(TW-6'd1))
                    x_rem <= x_rem ;
                else
                    x_rem <= x_rem-(TW-6'd1) ;
            end
            default: x_rem <= x_rem;
        endcase
    end
end
///xdiv
//x方向連減了幾次(商)
always @(posedge CLK) begin
    if(RST)
        xdiv_c <= 7'd0;
    else begin
        case (1'd1)
            ns[IDLE]: xdiv_c <= 7'd0;
            ns[S1]: xdiv_c <= 7'd0;
            ns[XDIV]:begin
                if(x_rem<(TW-6'd1))
                    xdiv_c <= xdiv_c;
                else
                    xdiv_c <= xdiv_c + 7'd1;
            end
            default:
                xdiv_c <= xdiv_c;
        endcase
    end
end

///ysum
//y方向累加之和
always @(posedge CLK) begin
    if(RST)begin
        y_sum <= 14'd0;
    end    else begin
        case (1'd1)
            ns[IDLE]:begin
                y_sum <= 14'd0;
            end
            ns[S1]:begin
                y_sum <= 14'd0;
            end
            ns[YSUM]:begin
                if(ysum_c == cnt_y)begin
                    y_sum <= y_sum;
                end
                else begin
                    y_sum <= y_sum + (SH-5'd1);
                end
            end 
            default:begin
                y_sum <= y_sum;
            end 
        endcase
    end
end
//y方向累加了幾次
always @(posedge CLK) begin
    if(RST)begin
        ysum_c <= 7'd0;
    end    else begin
        case (1'd1)
            ns[IDLE]:begin
                ysum_c <= 7'd0;
            end
            ns[S1]:begin
                ysum_c <= 7'd0;
            end
            ns[YSUM]:begin
                if(ysum_c == cnt_y)begin
                    ysum_c <= ysum_c;
                end
                else begin
                    ysum_c <= ysum_c + 7'd1;
                end
            end 
            default:begin
                ysum_c <= ysum_c;
            end 
        endcase
    end
end
///y_rem
//y方向連減取後剩下的餘數
always @(posedge CLK) begin
    if(RST)
        y_rem <= 14'd0;
    else begin
        case (1'd1)
            ns[IDLE]:y_rem <= 14'd0;
            ns[S1]: y_rem <= 14'd0;
            ns[YSUM]:begin
                if(ysum_c == cnt_y)
                    y_rem <= y_rem;
                else 
                    y_rem <= y_rem + (SH-5'd1);
            end
            ns[YDIV]:begin
                if(y_rem<(TH-6'd1))
                    y_rem <= y_rem ;
                else
                    y_rem <= y_rem-(TH-6'd1) ;
            end
            default: y_rem <= y_rem;
        endcase
    end
end
///ydiv
//y方向連減了幾次(商)
always @(posedge CLK) begin
    if(RST)
        ydiv_c <= 7'd0;
    else begin
        case (1'd1)
            ns[IDLE]:ydiv_c <= 7'd0;
            ns[S1]:
                ydiv_c <= 7'd0;
            ns[YDIV]:begin
                if(y_rem<(TH-6'd1))
                    ydiv_c <= ydiv_c;
                else
                    ydiv_c <= ydiv_c + 7'd1;
            end
            default:
                ydiv_c <= ydiv_c;
        endcase
    end
end

//en16 是否做完4組同一方向BIC後又做完另一方向的BIC
always @(posedge CLK) begin
    if(RST) en16 <= 1'd0;
    else begin
        case (1'd1)
            cs[S1]: en16 <= 1'b0;
            cs[WAIT_2]:en16 <= 1'b1;
            default: en16 <= en16;
        endcase
    end
end


//cnt_x(x方向計數器) 每經過一點+1
always @(posedge CLK) begin
    if(RST) cnt_x <= 6'd0;
    else begin
        case (1'd1)
            cs[WAIT_C]:begin
                if(ns[S1])begin
                        if(cnt_x == (TW-6'd1)) //如果算完一排則變0 開始計算下一排 此時下面的cnt_y+1
                            cnt_x <= 6'd0;
                        else //每經過一點+1
                            cnt_x <= cnt_x + 6'd1;
                end
                else cnt_x <= cnt_x;            
            end
            cs[WAIT_CC]:begin
                if(ns[S1]) begin
                        if(cnt_x == (TW-6'd1)) //如果算完一排則歸0 開始計算下一排  
                            cnt_x <= 6'd0;
                        else //每經過一點+1
                            cnt_x <= cnt_x + 6'd1;
                end
                else cnt_x <= cnt_x;            
            end
        endcase
    end
end

//cnt_y(y方向計數器) 每經過一排+1
always @(posedge CLK) begin
    if(RST) cnt_y <= 6'd0;
    else if(cs[OVER])
        cnt_y <= 6'd0;
    else begin
        case (1'd1)
            cs[WAIT_C]:begin
                if(ns[S1] == 1'd1)
                    if((cnt_y == (TH-6'd1)) && (cnt_x == (TW-6'd1))) //算到最後一點(右下角)後歸0
                        cnt_y <= 6'd0;
                    else if(cnt_x == (TW-6'd1)) //每經過一排+1
                        cnt_y <= cnt_y + 6'd1;
                    else 
                        cnt_y <= cnt_y ;
                else 
                    cnt_y <= cnt_y;
            end
            cs[WAIT_CC]:begin
                if(ns[S1] == 1'd1)
                    if((cnt_y == (TH-6'd1)) && (cnt_x == (TW-6'd1))) //算到最後一點(右下角)後歸0
                        cnt_y <= 6'd0;
                    else if(cnt_x == (TW-6'd1)) //每經過一排+1
                        cnt_y <= cnt_y + 6'd1;
                    else 
                        cnt_y <= cnt_y ;
                else 
                    cnt_y <= cnt_y;
            end
        endcase
    end
end

//cnt_p
//算BIC要拿4個點 這個計數器用來計算拿到第幾個點了 
always @(posedge CLK) begin
    if(RST) cnt_p <= 2'd0;
    else if(cs[P]) cnt_p <= cnt_p + 2'd1;
end

//cnt_p16(兩個方向都要做BIC時會用到的計數器)
//一個方向要做1次BIC要拿4個點 做4次BIC就要拿16個點 所以取名cnt_p16 但實際上只會數0~3
always @(posedge CLK) begin
    if(RST) cnt_p16 <= 2'd0;
    else if(cs[WAIT_C] && ((pin==center) && (!ns[WAIT_CC]))) cnt_p16 <= cnt_p16 + 2'd1;      
    else cnt_p16 <= cnt_p16; 
end

//控制rom
//inen
always @(posedge CLK) begin
    if(RST) inen <= 'd1;
    else begin
        case (1'd1)
            ns[INEN_s]:     inen <= 1'b0;
            ns[INEN_4p]:    inen <= 1'b0;
            default:        inen <= 1'b1;
        endcase
    end
end

//控制ram
//outen
always @(posedge CLK) begin
    if(RST) outen <= 'd1;
    else begin
        case (1'd1)
            ns[WAIT_C]:     outen<=1'b0;
            ns[WAIT_CC]:    outen<=1'd0;
            default:        outen<=1'b1;
        endcase
    end
end

//檢查訊號
//done
always @(posedge CLK) begin
    if(RST) DONE <= 'd0;
    else begin
        case (1'd1)
            ns[OVER]:       DONE<=1'b1;
            default:        DONE<=1'b0;
        endcase
    end
end


//x座標
//讀寫rom ram時的x座標
always @(posedge CLK) begin
    if(RST)begin
        X_T <= 7'd0;
    end
    else begin
        case (1'd1)
            cs[IDLE]:   X_T <= 7'd0; 
            cs[YDIV]: X_T <= H0 + xdiv_c;
            cs[P]:begin
                if((pin == left) || (pin == right)) //點剛好落在左右邊上時 X座標不須變動
                    X_T <= X_T;
                else begin
                    case (cnt_p)
                        2'd0:X_T <= X_T + 7'd1; //p2
                        2'd1:X_T <= X_T + 7'd1; //p3
                        2'd2:X_T <= X_T - 7'd3; //p0
                        2'd3:X_T <= X_T + 7'd1; 
                    endcase
                end                
            end
            default: X_T <= X_T;
        endcase
    end
end



//y座標
//讀寫rom ram時的y座標
always @(posedge CLK) begin
    if(RST)begin
        Y_T <= 7'd0;
    end
    else begin
        case (1'd1)
            cs[IDLE]:   Y_T <= 7'd0;
            cs[YDIV]:   Y_T <= V0 + ydiv_c;
            cs[P]:begin
                if((pin == top) || (pin == down)) //點剛好落在上下邊上時 y座標不須變動
                    Y_T <= Y_T;
                else begin
                    if((pin == left) || (pin == right)) //點剛好落在左右邊上時
                        begin
                            case (cnt_p)
                                2'd0:Y_T <= Y_T + 7'd1; //p2
                                2'd1:Y_T <= Y_T + 7'd1; //p3
                                2'd2:Y_T <= Y_T - 7'd3; //p0
                                2'd3:Y_T <= Y_T + 7'd1;
                                default:Y_T <= Y_T; 
                            endcase
                        end
                    else begin//取16 (點落在中間時)
                        if((cnt_p == 2'd3) && (~|cnt_p16 )) // cnt_p16 == 3'd0
                            Y_T <= Y_T + 7'd1;
                        else if((cnt_p == 2'd3) && (cnt_p16 == 2'd1))
                            Y_T <= Y_T + 7'd1;
                        else if((cnt_p == 2'd3) && (cnt_p16 == 2'd2))
                            Y_T <= Y_T - 7'd3;
                        else if((cnt_p == 2'd3) && (cnt_p16 == 2'd3))
                            Y_T <= Y_T - 7'd1;
                        else 
                            Y_T <= Y_T;
                    end
                end 
            end
            default: Y_T <= Y_T;
        endcase
    end
end

//運算
//p0 p1 p2 p3
always@(posedge CLK)begin
    if(RST)begin
        p0 <= 10'd0;
        p1 <= 10'd0;
        p2 <= 10'd0;
        p3 <= 10'd0;
    end
    else begin
        case (1'd1)
            cs[P]:begin
                case (cnt_p)
                    2'd0:begin
                        p0 <= p0;
                        p1 <= $signed({1'b0,Q_in,1'b0}); //1位符號，Ｑ_in，1位小數點
                        p2 <= p2;
                        p3 <= p3;
                    end 
                    2'd1:begin
                        p0 <= p0;
                        p1 <= p1;
                        p2 <= $signed({1'b0,Q_in,1'b0}); 
                        p3 <= p3;
                    end
                    2'd2:begin
                        p0 <= p0;
                        p1 <= p1;
                        p2 <= p2;
                        p3 <= $signed({1'b0,Q_in,1'b0}); 
                    end
                    2'd3:begin
                        p0 <= $signed({1'b0,Q_in,1'b0}); 
                        p1 <= p1;
                        p2 <= p2;
                        p3 <= p3;
                    end
                    default:begin
                        p0 <= p0;
                        p1 <= p1;
                        p2 <= p2;
                        p3 <= p3;
                    end
                endcase
            end
            default: begin
                p0 <= p0;
                p1 <= p1;
                p2 <= p2;
                p3 <= p3;
            end
        endcase
    end
end

//b0 b1 b2 b3 (單方向BIC計算的值存入b0~b3 再存入大P0~P3進行另一方向的BIC)
always@(posedge CLK)begin
    if(RST)begin
        b0 <= 10'd0;
        b1 <= 10'd0;
        b2 <= 10'd0;
        b3 <= 10'd0;
    end
    else begin
        case (1'd1)
            cs[WAIT]:begin
                if(pin == center)
                    case (cnt_p16)
                        2'd0:begin
                            b0 <= b0;
                            b1 <= $signed({1'b0,PA,1'b0}); 
                            b2 <= b2;
                            b3 <= b3;
                        end 
                        2'd1:begin
                            b0 <= b0;
                            b1 <= b1;
                            b2 <= $signed({1'b0,PA,1'b0}); 
                            b3 <= b3;
                        end
                        2'd2:begin
                            b0 <= b0;
                            b1 <= b1;  
                            b2 <= b2;
                            b3 <= $signed({1'b0,PA,1'b0});
                        end
                        2'd3:begin
                            b0 <= $signed({1'b0,PA,1'b0});
                            b1 <= b1;
                            b2 <= b2;
                            b3 <= b3;
                        end
                        default:begin
                            b0 <= b0;
                            b1 <= b1;
                            b2 <= b2;
                            b3 <= b3;
                        end
                    endcase
            end
            default: begin
                b0 <= b0;
                b1 <= b1;
                b2 <= b2;
                b3 <= b3;
            end
        endcase
    end
end

//P0 P1 P2 P3
always @(posedge CLK) begin
    if(RST)begin
        P0 = 10'd0;
        P1 = 10'd0;
        P2 = 10'd0;
        P3 = 10'd0;
    end
    else begin
        case (1'd1)
            ns[WAIT_C]:begin
                if(pin == center)
                    begin
                        P0 = b0;
                        P1 = b1;
                        P2 = b2;
                        P3 = b3;
                    end 
                else begin
                    P0 = p0;
                    P1 = p1;
                    P2 = p2;
                    P3 = p3;
                end
            end 
            default:begin
                P0 = p0;
                P1 = p1;
                P2 = p2;
                P3 = p3;
            end
        endcase
    end
    
end


//a,b,c,d 變動 P0123 
assign a = (P1 + (P1>>1)) + (P3>>1) - (P0>>1) - (P2+(P2>>1));//((3/2)*(p1-p2)) + ((1/2)*(p3-p0));
assign b = (P2 << 1) + P0 - (((P1 << 2) + P1)>>1) - ((P3)>>1); 
assign c = (P2>>1) - (P0>>1);//((1/2)*(p2-p0));
assign d = P1;



//
//x 變動x 第5頁算式裡的x 取小數點15位
always@(*)begin
    if((pin == top) || (pin == down))
        x = ((x_sum<<15)/(TW-1));
        //x = ((((SW-1)<<15)*cnt_x)/(TW-1));
    else if((pin == left) || (pin == right))
        x = ((y_sum<<15)/(TH-1));
        //x = ((((SH-1)<<15)*cnt_y)/(TH-1));
    else if(pin == center)
        if(ns[WAIT_CC] == 1'd1)
        x = ((y_sum<<15)/(TH-1));
        //x = ((((SH-1)<<15)*cnt_y)/(TH-1));
        else
        x = ((x_sum<<15)/(TW-1));
        //x = ((((SW-1)<<15)*cnt_x)/(TW-1));
    else 
        x = 15'd0;
end
//assign x = ((((SW-1)<<10)*cnt_x)/(TW-1));
assign x_2 = x*x; //x平方變小數點30位
assign x_3 = x_2*x; //x三次方便小數點45位
//全部變成 1位符號 45位小數 以便計算
assign x1 =  $signed({1'b0 , x , {30{1'b0}}}); 
assign x2 =  $signed({1'b0, x_2 , {15{1'b0}} });
assign x3 =  $signed({1'b0, x_3});

assign Pxe = (a*x3) + (b*x2) + (c*x1) + (d<<45);


always@(*)begin
    if(Pxe[150] ) //小於0(符號位為1)時 視為0
        PA = 8'd0;
    else begin //四捨五入
        if(Pxe[45])
            PA = (Pxe>>46) + 1'b1;
        else 
            PA = Pxe >> 46;
    end 
end

endmodule




