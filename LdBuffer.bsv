import Vector::*;
import Ehr::*;

import Types::*;
import MemTypes::*;

/* A load buffer is not an FIFO. Instead, it is associative. */

interface LdBuffer/*#(numeric type size)*/;
    method Action insert(TokenizedMemReq req, LdStatus status);
    // check if there is an address match
    method Bool search(Bit#(32) a);
    // retire load upon response
    method ActionValue#(TokenizedMemReq) remove(Bit#(32) a);
    // update load status
    method Action update(Bit#(32) a, LdStatus status);
    // check if load is in `Wb` or `FillReq` state
    method TypeUpdate usearch;
endinterface

(* synthesize *)
module mkLdBuffer(LdBuffer/*#(size)*/) /*provisos (Log#(size, 2))*/;
    let bufferSize = valueOf(LdBufferSize);
    Bit#(TAdd#(TLog#(LdBufferSize), 1)) _bufferSize = fromInteger(bufferSize);

    Vector#(LdBufferSize, Ehr#(3, LdStatus)) statusArray <- replicateM(mkEhr(Invalid));
    Vector#(LdBufferSize, Ehr#(3, TokenizedMemReq)) buffer <- replicateM(mkEhrU);
    Ehr#(3, Bit#(TAdd#(TLog#(LdBufferSize), 1))) cnt <- mkEhr(0);

    /* `remove` < `search` < `insert` < `update`
     *                                     CF
     *                                  `usearch`
     */
    method ActionValue#(TokenizedMemReq) remove(Bit#(32) a) if (cnt[0] != 0);
        Bit#(TLog#(LdBufferSize)) idx = 0;
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (buffer[i][0].req.addr == a)
                idx = fromInteger(i);
        end
        statusArray[idx][0] <= Invalid;
        cnt[0] <= cnt[0] - 1;
        return buffer[idx][0];
    endmethod

    method Action update(Bit#(32) a, LdStatus status);
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (statusArray[i][2] != Invalid && buffer[i][2].req.addr == a)
                statusArray[i][2] <= status;
        end
    endmethod

    method TypeUpdate usearch;
        TypeUpdate u = TypeUpdate{valid : False,
                                  status: ?,
                                  addr  : ?};
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (statusArray[i][2] == Wb || statusArray[i][2] == FillReq) begin
                u = TypeUpdate{valid : True,
                               status: statusArray[i][2],
                               addr  : buffer[i][2].req.addr};
            end
        end
        return u;
    endmethod

    method Bool search(Bit#(32) a);
        Bool s = False;
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (statusArray[i][1] != Invalid && buffer[i][1].req.addr == a)
                s = True;
        end
        return s;
    endmethod

    method Action insert(TokenizedMemReq req, LdStatus status) if (cnt[1] != _bufferSize);
        Bit#(TLog#(LdBufferSize)) idx = 0;
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (statusArray[i][1] == Invalid) begin
                idx = fromInteger(i);
            end
        end
        buffer[idx][1] <= req;
        statusArray[idx][1] <= status;
        cnt[1] <= cnt[1] + 1;
    endmethod
endmodule
