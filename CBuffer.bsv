import Vector::*;
import Ehr::*;


interface CBuffer;
    method ActionValue#(t) getToken();
    method Action put(Token idx, t data);
    method ActionValue#(t) getResult();
endinterface

module mkCBuffer#(size)(Cbuffer);
    let bufferSize = valueOf(size);
    Bit#(TAdd#(TLog(size), 1)) _bufferSize = fromInteger(_bufferSize);

    Vector#(size, Ehr#(3, Maybe(t))) buffer <- replicateM(mkEhr(tagged Invalid));
    Reg#(Bit#(TAdd#(TLog(size), 1))) iidx <- mkReg(0);
    Reg#(Bit#(TAdd#(TLog(size), 1))) ridx <- mkReg(0);
    Ehr#(2, Bit#(TAdd#(TLog(size), 1))) cnt <- mkEhr(0);
    // `getToken` < `put` < `getResult`
    method ActionValue#(t) getToken() if (cnt[0] != _bufferSize);
        buffer[iidx][0] <= tagged Invalid; // necessary?
        iidx <= iidx == _bufferSize - 1 ? 0 : iidx + 1;
        cnt[0] <= cnt[0] + 1;
        return iidx;
    endmethod

    method Action put(Token idx, t data);
        buffer[idx][1] <= tagged Valid data;
    endmethod

    method ActionValue#(t) getResult() if (cnt[1] != 0 && isValid(buffer[ridx][2]));
        buffer[ridx][2] <= tagged Invalid;
        ridx <= ridx == _bufferSize - 1 ? 0 : ridx + 1;
        cnt[1] <= cnt[1] - 1;
        return buffer[ridx][2];
    endmethod
endmodule
