import Ehr::*;
import FIFO::*;
import Vector::*;

import Types::*;
import MemTypes::*;


interface SLFIFO/*#(numeric type size)*/;
    //method Bool notEmpty;
    method TokenizedCacheReq first;
    method Action deq;

    method Bool search(Bit#(32) a);

    //method Bool notFull;
    method Action enq(TokenizedCacheReq req);

    //method Action clear;
endinterface

(* synthesize *)
module mkSLFIFO(SLFIFO/*#(size)*/) /*provisos (Log#(size, 2))*/;
    let bufferSize = valueOf(WaitBufferSize);
    Bit#(TAdd#(TLog#(WaitBufferSize), 1)) _bufferSize = fromInteger(bufferSize);

    Vector#(WaitBufferSize, Ehr#(2, Maybe#(TokenizedCacheReq))) buffer <- replicateM(mkEhr(tagged Invalid));
    Reg#(Bit#(TAdd#(TLog#(WaitBufferSize), 1)))    iidx <- mkReg(0); // insert index, a.k.a. tail
    Ehr#(2, Bit#(TAdd#(TLog#(WaitBufferSize), 1))) ridx <- mkEhr(0); // read index, a.k.a. head
    Ehr#(2, Bit#(TAdd#(TLog#(WaitBufferSize), 1))) cnt <- mkEhr(0);

    // `first` CF `deq` < `search` < `enq`

    method TokenizedCacheReq first() if (cnt[0] != 0);
        return fromMaybe(TokenizedCacheReq{token: 0,
                                           req: CacheReq{word_byte: 4'hF,
                                                         addr: 32'hFFFFFFFF,
                                                         data: 32'hFFFFFFFF}},
                         buffer[ridx[0]][0]);
    endmethod

    method Action deq() if (cnt[0] != 0);
        buffer[ridx[0]][0] <= tagged Invalid;
        ridx[0] <= ridx[0] == _bufferSize - 1 ? 0 : ridx[0] + 1;
        cnt[0] <= cnt[0] - 1;
    endmethod

    method Bool search(Bit#(32) a);
        Bool exist = False;
        Bit#(TAdd#(TLog#(WaitBufferSize), 1)) idx = ridx[1];
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            let addr = fromMaybe(TokenizedCacheReq{token: 0,
                                                   req: CacheReq{word_byte: 4'hF,
                                                                 addr: 32'hFFFFFFFF,
                                                                 data: 32'hFFFFFFFF}},
                                 buffer[idx][1]).req.addr;
            if (isValid(buffer[idx][1]) && addr == a) begin
                exist = True;
            end
            idx = idx == _bufferSize - 1 ? 0 : idx + 1;
        end
        return exist;
    endmethod

    method Action enq(TokenizedCacheReq req) if (cnt[1] != _bufferSize);
        buffer[iidx[1]][1] <= tagged Valid req;
        iidx <= iidx == _bufferSize - 1 ? 0 : iidx + 1;
        cnt[1] <= cnt[1] + 1;
    endmethod
endmodule
