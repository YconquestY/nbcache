import RegFile::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import StBuffer::*;
import LdBuffer::*;
import SLFIFO::*;
import Types::*;
import MemTypes::*;


interface NBCache;
    method Action putFromProc(TokenizedCacheReq e);
    method ActionValue#(TokenizedWord) getToProc();
    // TODO: tokenized if multi-level cache
    method ActionValue#(MemReq) getToMem();
    method Action putFromMem(MainMemResp e);
endinterface

(* synthesize *)
module mkNBCache(NBCache);
    //RegFile#(LineIndex, LineState) stateArray <- mkRegFileFull;
    Vector#(128, Reg#(LineState)) stateArray <- replicateM(mkReg(Invalid));
    RegFile#(LineIndex, LineTag)   tagArray   <- mkRegFileFull;
    RegFile#(LineIndex, LineData)  dataArray  <- mkRegFileFull;

    StBuffer/*#(StBufferSize)*/ stBuffer <- mkStBuffer;
    LdBuffer/*#(LdBufferSize)*/ ldBuffer <- mkLdBuffer;
    SLFIFO/*#(WaitBufferSize)*/ waitBuffer <- mkSLFIFO;
    // TODO: tokenized if multi-level cache
    FIFOF#(MemReq) wbQ <- mkFIFOF;
    FIFOF#(MemReq) memReqQ <- mkFIFOF;
    FIFO#(MemResp) memRespQ <- mkFIFO;

    FIFO#(HitResp)  hitQ  <- mkBypassFIFO;
    FIFO#(Bit#(32)) addrQ <- mkFIFO; // TODO: memory response OoO for multi-level cache

    Reg#(Bool) processWaitBuffer <- mkReg(False);
    // store hit
    // A store request that hits also goes into `hitQ`, but the processor do
    // not expect write response. This `rule` handles these store hits in `hitQ`.
    rule stHit (hitQ.first.req.word_byte != 4'h0);
        let req = hitQ.first.req; hitQ.deq;
        let parsedAddr = parseAddress(req.addr);
        // handle byte enable
        let line = dataArray.sub(parsedAddr.index);
        Vector#(BytePerWord, Byte) from = unpack(line[parsedAddr.woffset]);
        Vector#(BytePerWord, Byte) to   = unpack(req.data);
        for (Integer bo = 0; bo < valueOf(BytePerWord); bo = bo + 1) begin
            if (unpack(req.word_byte[bo]))
                from[bo] = to[bo];
        end
        line[parsedAddr.woffset] = pack(from);

        dataArray.upd(parsedAddr.index, line);
        //stateArray.upd(parsedAddr.index, Dirty);
        stateArray[parsedAddr.index] <= Dirty;
    endrule
    
    rule ldBufferUpdate;
        let u = ldBuffer.usearch;
        if (u.valid) begin
            if (u.status == FillReq) begin // normal load
                memReqQ.enq(MemReq{word_byte: 4'h0,
                                   addr: u.addr,
                                   data: ? /*tagged None*/});
                ldBuffer.update(u.addr, FillResp);
            end
            else begin // cache line eviction
                let parsedAddr = parseAddress(u.addr);
                // dirty line writeback
                wbQ.enq(MemReq{word_byte: 4'hF, // does not matter as long as not 0
                               addr: {tagArray.sub(parsedAddr.index), parsedAddr.index, ?},
                               data: tagged Eviction pack(dataArray.sub(parsedAddr.index))});
                memReqQ.enq(MemReq{word_byte: 4'h0,
                                   addr: u.addr,
                                   data: ? /*tagged None*/});
                ldBuffer.update(u.addr, FillResp);
            end
        end
    endrule
    
    rule memRespAvailable (!processWaitBuffer);
        let data = memRespQ.first.data;
        LineData line = unpack(data);

        let addr = memRespQ.first.addr;
        let parsedAddr = parseAddress(addr);

        //stateArray.upd(parsedAddr.index, Clean);
        stateArray[parsedAddr.index] <= Clean;
        tagArray.upd(parsedAddr.index, parsedAddr.tag);
        dataArray.upd(parsedAddr.index, line);

        let retiredReq <- ldBuffer.remove(addr); // `TokenizedMemReq`
        hitQ.enq(HitResp{token: retiredReq.token,
                         req: CacheReq{word_byte: retiredReq.req.word_byte,
                                       addr: ?,
                                       data: ?},
                         data: tagged Valid line[parsedAddr.woffset]});
        if (waitBuffer.search(addr))
            processWaitBuffer <= True;
        else
            memRespQ.deq;
    endrule

    Reg#(Bool) tmpWait <- mkReg(False);
    Reg#(TokenizedCacheReq) tmpReq <- mkRegU;

    rule traverseWaitBuffer (processWaitBuffer && !tmpWait);
        let data = memRespQ.first.data;
        let addr = memRespQ.first.addr;

        let req = waitBuffer.first; waitBuffer.deq; // `TokenizedCacheReq`
        if (req.req.addr == addr) begin
            LineData line = unpack(data);
            hitQ.enq(HitResp{token: req.token,
                             req  : req.req,
                             data : tagged Valid line[parseAddress(addr).woffset]});
        end
        else begin
            //waitBuffer.enq(req); // push request back to wait buffer
            tmpReq <= req;
            tmpWait <= True;
        end
        if (!waitBuffer.search(addr)) begin
            processWaitBuffer <= False;
            memRespQ.deq;
        end
    endrule

    rule tmp (tmpWait);
        waitBuffer.enq(tmpReq);
        tmpWait <= False;
    endrule

    rule stBufferRemove;
        let req <- stBuffer.remove; // `MemReq`
        let data = case (req.data) matches
                       tagged Store .word: word;
                       default: 32'hFFFFFFFF;
                   endcase;
        //$display("SB remove address %x with data %x and byte enable %b to wbQ", req.addr, data, req.word_byte);
        wbQ.enq(req);
    endrule

    method Action putFromProc(TokenizedCacheReq e) if (!processWaitBuffer && !tmpWait);
        let parsedAddr = parseAddress(e.req.addr);

        let state = stateArray[parsedAddr.index]/*.sub(parsedAddr.index)*/;
        let tagMatch = tagArray.sub(parsedAddr.index) == parsedAddr.tag;

        let sbMatch = stBuffer.search(e.req.addr); // `Maybe#(Word)`
        let lbMatch = ldBuffer.search(e.req.addr); // Boolean

        if (state != Invalid && tagMatch) begin
            hitQ.enq(HitResp{token: e.token,
                             req  : e.req,
                             data : tagged Invalid}); // directly read from register from RF
            //$display("hit");
        end else if (lbMatch) begin
            waitBuffer.enq(e);
            //$display("load buffer address match");
        end else if (e.req.word_byte != 4'h0) begin // Store is not tokenized.
            stBuffer.insert(MemReq{word_byte: e.req.word_byte,
                                   addr: e.req.addr,
                                   data: tagged Store e.req.data});
            //$display("SB insert address %x with data %x and byte enable %b", e.req.addr, e.req.data, e.req.word_byte);
        end else if (e.req.word_byte == 4'h0 && // load
                 isValid(sbMatch)) begin    // forwarding
            hitQ.enq(HitResp{token: e.token,
                             req  : e.req,
                             data : sbMatch});
        end else begin
            ldBuffer.insert(TokenizedMemReq{token: e.token,
                                            req: MemReq{word_byte: 4'h0, // guaranteed to be a load
                                                        addr: e.req.addr,
                                                        data: ? /*tagged None*/}},
                            state == Dirty ? Wb : FillReq);
        end
    endmethod

    // load
    method ActionValue#(TokenizedWord) getToProc() if (hitQ.first.req.word_byte == 4'h0);
        let req = hitQ.first.req; hitQ.deq;
        let parsedAddr = parseAddress(req.addr);
        return TokenizedWord{token: hitQ.first.token,
                             resp : isValid(hitQ.first.data) ? fromMaybe(32'hFFFFFFFF,
                                                                         hitQ.first.data)
                                                             : dataArray.sub(parsedAddr.index)[parsedAddr.woffset]};
    endmethod

    // Store has higher priority than load for the sake of forwarding.
    method ActionValue#(MemReq) getToMem() if (wbQ.notEmpty || memReqQ.notEmpty);
        if (wbQ.notEmpty) begin
            wbQ.deq;
            return wbQ.first;
        end
        else begin
            let req = memReqQ.first; memReqQ.deq;
            addrQ.enq(req.addr); // TODO: memory response OoO for multi-level cache
            return req;
        end
    endmethod

    method Action putFromMem(MainMemResp e);
        // TODO: memory response OoO for multi-level cache
        let addr = addrQ.first; addrQ.deq;
        memRespQ.enq(MemResp{addr: addr,
                             data: e});
    endmethod
endmodule
