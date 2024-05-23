import Vector::*;
import Ehr::*;

import MemTypes::*;

/* A load buffer is not an FIFO. Instead, it is associative. */

interface LdBuffer#(numeric type size);
    method Action insert(TokenizedCacheReq req, LdStatus status);
    // check if there is an address match
    method Bool search(Bit#(32) a);
    // retire load upon response
    method ActionValue#(TokenizedCacheReq) remove(Addr a);
    // update load status
    method Action update(Addr a, LdStatus status);
    // check if load is in `Wb` or fill? state
    method TypeUpdate usearch;
endinterface

module mkLdBuffer(LdBuffer#(size));
    let bufferSize = valueOf(size);
    Bit#(TAdd#(TLog#(size), 1)) _bufferSize = fromInteger(bufferSize);

    Vector#(size, Ehr#(3, LdStatus)) statusArray <- replicateM(mkEhr(Invalid));
    Vector#(size, Ehr#(3, TokenizedCacheReq)) buffer <- replicateM(mkEhrU);
    Ehr#(3, Bit#(TAdd#(TLog#(size), 1))) cnt <- mkEhr(0);

    /* `remove` < `search` < `insert` < `update`
     *                                     CF
     *                                  `usearch`
     */
    method ActionValue#(TokenizedCacheReq) remove(Bit#(32) a) if (cnt[0] != 0);
        Bit#(TLog#(size)) idx = 0;
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
        let u = TypeUpdate{valid : False,
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
        let s = False;
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (statusArray[i][1] != Invalid && buffer[i][1].req.addr == a)
                s = True;
        end
        return s;
    endmethod

    method Action insert(TokenizedCacheReq req, LdStatus status) if (cnt[1] != _bufferSize);
        Bit#(TLog#(size)) idx = 0;
        for (Integer i = 0; i < bufferSize; i = i + 1) begin
            if (statusArray[i][1] == Invalid) begin
                idx = fromInteger(i);
                buffer[idx][1] <= req;
                statusArray[idx][1] <= status;
                cnt[1] <= cnt[1] + 1;
            end
        end
    endmethod
endmodule
