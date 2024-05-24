typedef 4 BytePerWord;
/* TODO: constrain `CBufferSize` = `StBufferSize` +
 *                                 `LdBufferSize` +
 *                                 `WaitBufferSize`
 *       at compile time
 */
typedef 8 CBufferSize;

typedef 2 StBufferSize;
typedef 2 LdBufferSize;
typedef 4 WaitBufferSize;
