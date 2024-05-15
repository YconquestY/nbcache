import Vector::*;


// Types used in L1 interface
typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { Bit#(4) word_byte; Bit#(32) addr; Bit#(32) data; } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef Bit#(512) MainMemResp;
typedef Bit#(32) Word;

// (Curiosity Question: CacheReq address doesn't actually need to be 32 bits. Why?)

// Helper types for implementation (L1 cache):
typedef enum {
    Invalid,
    Clean,
    Dirty
} LineState deriving (Eq, Bits, FShow);

// You should also define a type for LineTag, LineIndex. Calculate the appropriate number of bits for your design.
typedef Bit#(19) LineTag; // 32b address - 2b BO - 4b WO - 7B index
typedef Bit#(7) LineIndex;
// You may also want to define a type for WordOffset, since multiple Words can live in a line.
typedef Bit#(4) WordOffset; // 16 words per line

// You can translate between Vector#(16, Word) and Bit#(512) using the pack/unpack builtin functions.
typedef Vector#(16, Word) LineData; // optional

// Optional: You may find it helpful to make a function to parse an address into its parts.
// e.g.,
typedef struct {
    LineTag tag;
    LineIndex index;
    WordOffset woffset;
} ParsedAddress deriving (Bits, Eq);

function ParsedAddress parseAddress(Bit#(32) address);
    return ParsedAddress {tag: address[31:13],
                          index: address[12:6], // 128 lines
                          woffset: address[5:2]};
endfunction

// and define whatever other types you may find helpful.
typedef enum {WaitCAUResp, SendReq, WaitMemResp} ReqStatus deriving (Bits, Eq, FShow);
typedef enum {Ready, WaitResp, WaitUpdate} CAUStatus deriving (Bits, Eq, FShow);

typedef struct {
    HitMissType hitMiss;
    Word        ldValue;
    CacheLine   line;
} CAUResp deriving (Bits, Eq, FShow);

typedef enum {LdHit, StHit, Miss} HitMissType deriving (Bits, Eq, FShow);
typedef struct {
    LineState state;
    LineTag   tag;
    LineData  data;
} CacheLine deriving (Bits, Eq, FShow);

// Helper types for implementation (L2 cache):
typedef Bit#(18) LineTag2; // 26b address - 8b index
typedef Bit#(8) LineIndex2;

typedef struct {
    LineTag2   tag;
    LineIndex2 index;
} ParsedAddress2 deriving (Bits, Eq);

function ParsedAddress2 parseAddress2(Bit#(26) address);
    return ParsedAddress2{tag: address[25:8],
                          index: address[7:0]}; // 256 lines
endfunction

typedef struct {
    HitMissType hitMiss;
    CacheLine2  line;
} CAUResp2 deriving (Bits, Eq, FShow);

typedef struct {
    LineState   state;
    LineTag2    tag;
    MainMemResp data;
} CacheLine2 deriving (Bits, Eq, FShow);
