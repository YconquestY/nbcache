import Vector::*;
import Ehr::*;

/* A store buffer is an actual FIFO. */

interface StBuffer#(numeric type size);
    method Action insert(MemReq req); // on store miss
    /* Associatively search for load address for load forwarding
     * The return type `Maybe#` carries indicates both search success and data.
     */
    method Maybe#(Word) search(Bit#(26) a);
    method ActionValue#(MemReq) remove; // popped to `wbQ`
endinterface

module mkStBuffer(StBuffer#(StBufferSize));
    let bufferSize = valueOf(size);
    Bit#(TAdd#(TLog#(size), 1)) _bufferSize = fromInteger(bufferSize);

    Vector#(size, Ehr#(2, Maybe#(MemReq))) buffer <- replicateM(mkEhr(tagged Invalid));
    Reg#(Bit#(TAdd#(TLog#(size), 1)))    iidx <- mkReg(0); // insert index, a.k.a. tail
    Ehr#(2, Bit#(TAdd#(TLog#(size), 1))) ridx <- mkEhr(0); // read index, a.k.a. head
    Ehr#(2, Bit#(TAdd#(TLog#(size), 1))) cnt  <- mkEhr(0);

    // `remove` < `search` < `insert`

    method ActionValue#(MemReq) remove if (cnt[0] != 0);
        buffer[ridx[0]][0] <= tagged Invalid;
        ridx[0] <= ridx[0] == _bufferSize - 1 ? 0 : ridx[0] + 1;
        cnt[0] <= cnt[0] - 1;
        return fromMaybe(buffer[ridx[0]][0]);
    endmethod

    method Maybe#(Word) search(Bit#(26) a);
        Maybe#(Word) m = tagged Invalid;
        let idx = ridx[1];
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (isValid(buffer[idx][1]) &&
                fromMaybe(buffer[idx][1]).addr == a) begin
                m = tagged Valid (fromMaybe(buffer[idx][1]).data);
            end
            idx = idx + 1;
        end
        return m;
    endmethod

    method Action insert(MemReq req) if (cnt[1] != _bufferSize);
        buffer[iidx][1] <= tagged Valid req;
        iidx <= iidx == _bufferSize - 1 ? 0 : iidx + 1;
        cnt[1] <= cnt[1] + 1;
    endmethod
endmodule
