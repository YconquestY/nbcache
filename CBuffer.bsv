import Vector::*;
import Ehr::*;

import Types::*;
import MemTypes::*;


interface CBuffer/*#(numeric type size)*/;
    method ActionValue#(Token) getToken();
    method Action put(Token idx, Word data);
    method ActionValue#(Word) getResult();
endinterface

(* synthesize *)
module mkCBuffer(CBuffer/*#(size)*/) /*provisos (Log#(size, 2))*/;
    let bufferSize = valueOf(CBufferSize);
    Bit#(TAdd#(TLog#(CBufferSize), 1)) _bufferSize = fromInteger(bufferSize);

    Vector#(CBufferSize, Ehr#(3, Maybe#(Word))) buffer <- replicateM(mkEhr(tagged Invalid));
    Reg#(Bit#(TAdd#(TLog#(CBufferSize), 1))) iidx <- mkReg(0); // insert index, a.k.a. tail
    Reg#(Bit#(TAdd#(TLog#(CBufferSize), 1))) ridx <- mkReg(0); // read index, a.k.a. head
    Ehr#(2, Bit#(TAdd#(TLog#(CBufferSize), 1))) cnt <- mkEhr(0);

    // `getToken` < `put` < `getResult`

    method ActionValue#(Token) getToken() if (cnt[0] != _bufferSize);
        buffer[iidx][0] <= tagged Invalid;
        iidx <= iidx == _bufferSize - 1 ? 0 : iidx + 1;
        cnt[0] <= cnt[0] + 1;
        return iidx;
    endmethod

    method Action put(Token idx, Word data);
        buffer[idx][1] <= tagged Valid data;
    endmethod

    method ActionValue#(Word) getResult() if (cnt[1] != 0 && isValid(buffer[ridx][2]));
        buffer[ridx][2] <= tagged Invalid;
        ridx <= ridx == _bufferSize - 1 ? 0 : ridx + 1;
        cnt[1] <= cnt[1] - 1;
        return fromMaybe(32'hFFFFFFFF,
                         buffer[ridx][2]);
    endmethod
endmodule
