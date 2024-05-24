import BRAM::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;

import RVUtil::*;
import DelayLine::*;
import Types::*;
import MemTypes::*;

interface MainMem;
    method Action put(MemReq req);
    method ActionValue#(MainMemResp) get();
endinterface

interface MainMemFast;
    method Action put(CacheReq req);
    method ActionValue#(Word) get();
endinterface

module mkMainMemFast(MainMemFast);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "mem.vmh";
    BRAM1PortBE#(Bit#(30), Word, 4) bram <- mkBRAM1ServerBE(cfg);
    DelayLine#(10, Word) dl <- mkDL(); // Delay by 20 cycles

    rule deq;
        let r <- bram.portA.response.get();
        dl.put(r);
        // $display("REF RESP", fshow(r));
    endrule    

    method Action put(CacheReq req);
        // $display("REF REQ", fshow(req));
        bram.portA.request.put(BRAMRequestBE{
                    writeen: req.word_byte,
                    responseOnWrite: False,
                    address: req.addr[31:2],
                    datain: req.data});
    endmethod

    method ActionValue#(Word) get();
        let r <- dl.get();
        return r;
    endmethod
endmodule

typedef enum { Ready, Busy } MainMemState deriving (Bits, Eq, FShow);
typedef enum { Ld, StWord } LdPurpose deriving (Bits, Eq, FShow);

(* synthesize *)
module mkMainMem(MainMem);
    BRAM_Configure cfg = defaultValue();
    cfg.loadFormat = tagged Hex "memlines.vmh";
    BRAM1Port#(Bit#(26), MainMemResp) bram <- mkBRAM1Server(cfg);

    DelayLine#(20, MainMemResp) dl <- mkDL(); // Delay by 20 cycles

    Reg#(MainMemState) state <- mkReg(Ready);
    FIFO#(MemReq) reqQ <- mkFIFO;
    FIFO#(LdPurpose) ldQ <- mkFIFO;

    rule resp (state == Ready || ldQ.first == Ld);
        let r <- bram.portA.response.get();
        dl.put(r);
        // $display("GOT FROM MM TO DL1 ",fshow(r));
        ldQ.deq;
    endrule

    rule store (state == Busy && ldQ.first == StWord);
        let req = reqQ.first; reqQ.deq;
        let parsedAddr = parseAddress(req.addr);

        let r <- bram.portA.response.get;
        LineData line = unpack(r);
        Vector#(BytePerWord, Byte) from = unpack(line[parsedAddr.woffset]);
        Vector#(BytePerWord, Byte) to = case (req.data) matches
                                            tagged Store .word: unpack(word);
                                            default: unpack(32'hFFFFFFFF);
                                        endcase;
        for (Integer bo = 0; bo < valueOf(BytePerWord); bo = bo + 1) begin
            if (unpack(req.word_byte[bo]))
                from[bo] = to[bo];
        end
        line[parsedAddr.woffset] = pack(from);
        bram.portA.request.put(BRAMRequest{
            write: True,
            responseOnWrite: False,
            address: {parsedAddr.tag, parsedAddr.index},
            datain: pack(line)
        });
        //$display("SENT TO MM1 WITH ",fshow(req));
        ldQ.deq;
        state <= Ready;
    endrule

    method Action put(MemReq req) if (state == Ready);
        let addr = req.addr[31:6]; 
        if (req.word_byte == 4'h0) begin // load
            bram.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: addr,
                datain: ?
            });
            //$display("SENT TO MM1 WITH ",fshow(req));
            ldQ.enq(Ld);
        end
        else if (req.data matches tagged Eviction .line) begin // cache line eviction
            bram.portA.request.put(BRAMRequest{
                write: True,
                responseOnWrite: False,
                address: addr,
                datain: line
            });
            //$display("SENT TO MM1 WITH ",fshow(req));
        end
        else begin // store word
            bram.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: addr,
                datain: ?
            });
            ldQ.enq(StWord);
            reqQ.enq(req);

            state <= Busy;
        end
    endmethod

    method ActionValue#(MainMemResp) get();
        let r <- dl.get();
        //$display("GOT FROM DL1 TO CACHE ",fshow(r));
        return r;
    endmethod

endmodule

