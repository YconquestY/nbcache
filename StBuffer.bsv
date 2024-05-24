import Vector::*;
import Ehr::*;

import Types::*;
import MemTypes::*;

/* A store buffer looks like a FIFO. */

interface StBuffer/*#(numeric type size)*/;
    method Action insert(MemReq req); // on store miss
    /* Associatively search for load address for load forwarding
     * The return type `Maybe#` carries indicates both search success and data.
     */
    method Maybe#(Word) search(Bit#(32) a);
    method ActionValue#(MemReq) remove; // popped to `wbQ`
endinterface

(* synthesize *)
module mkStBuffer(StBuffer/*#(size)*/) /*provisos (Log#(size, 2))*/;
    let bufferSize = valueOf(StBufferSize);
    Bit#(TAdd#(TLog#(StBufferSize), 1)) _bufferSize = fromInteger(bufferSize);

    Vector#(StBufferSize, Ehr#(2, Maybe#(MemReq))) buffer <- replicateM(mkEhr(tagged Invalid));
    Reg#(Bit#(TAdd#(TLog#(StBufferSize), 1)))    iidx <- mkReg(0); // insert index, a.k.a. tail
    Ehr#(2, Bit#(TAdd#(TLog#(StBufferSize), 1))) ridx <- mkEhr(0); // read index, a.k.a. head
    Ehr#(2, Bit#(TAdd#(TLog#(StBufferSize), 1))) cnt  <- mkEhr(0);

    // `remove` < `search` < `insert`

    method ActionValue#(MemReq) remove if (cnt[0] != 0);
        buffer[ridx[0]][0] <= tagged Invalid;
        ridx[0] <= ridx[0] == _bufferSize - 1 ? 0 : ridx[0] + 1;
        cnt[0] <= cnt[0] - 1;
        return fromMaybe(MemReq{word_byte: 4'hF,
                                addr: 32'hFFFFFFFF,
                                data: tagged Store 32'hFFFFFFFF},
                         buffer[ridx[0]][0]);
    endmethod

    method Maybe#(Word) search(Bit#(32) a);
        Maybe#(Word) m = tagged Invalid;
        Bit#(TAdd#(TLog#(StBufferSize), 1)) idx = ridx[1];
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            let req = fromMaybe(MemReq{word_byte: 4'hF,
                                       addr: 32'hFFFFFFFF,
                                       data: tagged Store 32'hFFFFFFFF},
                                buffer[idx][1]);
            if (isValid(buffer[idx][1]) && req.addr == a) begin
                m = case (req.data) matches
                        tagged Store .word: tagged Valid word;
                        default: tagged Valid 32'hFFFFFFFF;
                    endcase;
            end
            idx = (idx == _bufferSize) ? 0 : idx + 1;
        end
        return m;
    endmethod

    method Action insert(MemReq req) if (cnt[1] != _bufferSize);
        buffer[iidx][1] <= tagged Valid req;
        iidx <= iidx == _bufferSize - 1 ? 0 : iidx + 1;
        cnt[1] <= cnt[1] + 1;
    endmethod
endmodule
