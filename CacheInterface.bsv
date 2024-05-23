import CBuffer::*;
import NBCache::*;
import Types::*;
import MemTypes::*;


interface NBCache32;
    method Action putFromProc(CacheReq e);
    method ActionValue#(Word) getToProc();
    // TODO: tokenized if multi-level cache
    method ActionValue#(MemReq) getToMem();
    method Action putFromMem(MemResp e);
endinterface

(* synthesize *)
module mkNBCache32(NBCache32);
    CBuffer cBuffer <- mkCBuffer(CBufferSize);
    NBCache nbCache <- mkNBCache;

    rule nbCacheResp;
        let tokenizedResp <- nbCache.getToProc;
        cBuffer.put(tokenizedResp.token, tokenizedResp.resp);
    endrule

    method Action putFromProc(CacheReq e);
        let token <- cBuffer.getToken;
        nbCache.putFromProc(TokenizedCacheReq{token: token,
                                              req: e});
    endmethod

    method ActionValue#(Word) getToProc();
        return cBuffer.getResult();
    endmethod

    method ActionValue#(MemReq) getToMem();
        return nbCache.getToMem();
    endmethod

    method Action putFromMem(MemResp e);
        nbCache.putFromMem(e);
    endmethod
endmodule
