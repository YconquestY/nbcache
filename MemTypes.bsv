import Vector::*;
import Types::*;


typedef Bit#(TAdd#(TLog#(CBufferSize), 1)) Token;

// L1$ request

typedef struct {
    Bit#(4)  word_byte; // 0 for read
    Bit#(32) addr;
    Bit#(32) data;
} CacheReq deriving (Eq, FShow, Bits, Bounded);

typedef struct {
    Token token;
    CacheReq req;
} TokenizedCacheReq deriving (Bits, Eq, FShow, Bounded);

// L1$ response

typedef Bit#(32) Word;
typedef struct {
    Token token;
    Word  resp;
} TokenizedWord deriving (Bits, Eq, FShow);

typedef enum {
    Invalid,
    Wb, // ?
    FillReq,
    FillResp
} LdStatus deriving (Bits, Eq, FShow);

typedef struct {
    Bool     valid;
    LdStatus status;
    Bit#(32) addr;
} TypeUpdate deriving (Bits, Eq, FShow);

typedef struct {
    Token token;
    CacheReq req;
    Maybe#(Word) data;
} HitResp deriving (Bits, Eq, FShow);

/* Unlike lab 4a, the non-blocking cache adopts write-miss-no-allocate policy.
 * For a normal store, we cannot know in advanced the entire line to write to
 * memory, whereas cache line writeback evicts the entire line.
 */
typedef union tagged {
    //void None;
    Word Store;
    Bit#(512) Eviction;
} MemTraffic deriving (Eq, FShow, Bits, Bounded);

/* We also have to consider byte enable issue associated with a store. Similar
 * to `CacheReq`, when `word_byte` is 0, the request is a load; otherwise, data
 * are written to memory, whose type is determined by tag of `data` field.
 */
typedef struct {
    Bit#(4) word_byte;
    Bit#(32) addr;
    MemTraffic data;
} MemReq deriving (Eq, FShow, Bits, Bounded);

typedef struct {
    Token token;
    MemReq req;
} TokenizedMemReq deriving (Bits, Eq, FShow, Bounded);

/* In the cache-memory interface (`CacheInterface`), a `MemReq` is checked. If
 * its `data` tag is `Eviction`, simply write the line back to memory.
 * Otherwise, first load the line from memory, modify the corresponding word
 * (considering byte enable), and update memory with the written line.
 *
 * Either way, remember to explicitly transform `MemReq` to `MainMemReq`.
 */
typedef struct { Bit#(1) write; Bit#(26) addr; Bit#(512) data; } MainMemReq deriving (Eq, FShow, Bits, Bounded);

typedef Bit#(512) MainMemResp;
typedef struct {
    Bit#(32) addr;
    MainMemResp data;
} MemResp deriving (Eq, FShow, Bits);

typedef Bit#(8) Byte;

typedef enum {
    Invalid,
    Clean,
    Dirty
} LineState deriving (Eq, Bits, FShow);

typedef Bit#(19) LineTag; // 32b address - 2b BO - 4b WO - 7B index
typedef Bit#(7) LineIndex;
typedef Bit#(4) WordOffset; // 16 words per line

// You can translate between Vector#(16, Word) and Bit#(512) using the pack/unpack builtin functions.
typedef Vector#(16, Word) LineData;

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
