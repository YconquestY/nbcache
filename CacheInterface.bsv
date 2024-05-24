import CBuffer::*;
import NBCache::*;
import Types::*;
import MemTypes::*;


interface NBCache32;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
    // TODO: tokenized if multi-level cache
    method ActionValue#(MemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkNBCache32(NBCache32);
    CBuffer/*#(CBufferSize)*/ cBuffer <- mkCBuffer;
    NBCache nbCache <- mkNBCache;

    rule nbCacheResp;
        let tokenizedResp <- nbCache.getToProc;
        cBuffer.put(tokenizedResp.token, tokenizedResp.resp);
    endrule

    method Action putFromProc(CacheReq e);
        Token token = ?;
        if (e.word_byte == 4'h0) // load
            token <- cBuffer.getToken;
        else // store: no write response; do not allocate complete buffer slot
            token = 0;
        //$display("");
        nbCache.putFromProc(TokenizedCacheReq{token: token,
                                              req: e});
    endmethod

    method ActionValue#(Word) getToProc();
        let resp <- cBuffer.getResult;
        return resp;
    endmethod

    method ActionValue#(MemReq) getToMem();
        let req <- nbCache.getToMem;
        let data = case (req.data) matches
                       tagged Store .word: word;
                       default: 32'hFFFFFFFF;
                   endcase;
        //$display("write MEM address %x with data %x and byte enable %b", req.addr, data, req.word_byte);
        return req;
    endmethod

    method Action putFromMem(MainMemResp e);
        nbCache.putFromMem(e);
    endmethod
endmodule
