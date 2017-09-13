module nbuff.pipe;

private:
import std.algorithm;
import std.array;
import std.conv;
import std.experimental.logger;
import std.exception;
import std.format;
import std.range;
import std.range.primitives;
import std.string;
import std.stdio;
import std.traits;
import std.zlib;
import std.datetime;
import std.socket;
import core.stdc.errno;

import nbuff.buffer;

alias InDataHandler = DataPipeIface;

public class ConnectError: Exception {
    this(string message, string file =__FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow {
        super(message, file, line, next);
    }
}

class DecodingException: Exception {
    this(string message, string file =__FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow {
        super(message, file, line, next);
    }
}

public class TimeoutException: Exception {
    this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow {
        super(message, file, line, next);
    }
}

public class NetworkException: Exception {
    this(string message, string file = __FILE__, size_t line = __LINE__, Throwable next = null) @safe pure nothrow {
        super(message, file, line, next);
    }
}

/**
 * DataPipeIface can accept some data, process, and return processed data.
 */
public interface DataPipeIface {
    /// Is there any processed data ready for reading?
    bool empty();
    /// Put next data portion for processing
    //void put(E[]);
    void put(in BufferChunk);
    /// Get any ready data
    BufferChunk get();
    /// Signal on end of incoming data stream.
    void flush();
}

/**
 * DataPipe is a pipeline of data processors, each accept some data, process it, and put result to next element in line.
 * This class used to combine different Transfer- and Content- encodings. For example: unchunk transfer-encoding "chunnked",
 * and uncompress Content-Encoding "gzip".
 */
public class DataPipe : DataPipeIface {

    DataPipeIface[] pipe;
    Buffer          buffer;
    /// Append data processor to pipeline
    /// Params:
    /// p = processor

    final void insert(DataPipeIface p) {
        pipe ~= p;
    }

    final BufferChunk[] process(DataPipeIface p, BufferChunk[] data) {
        BufferChunk[] result;
        data.each!(e => p.put(e));
        while(!p.empty()) {
            result ~= p.get();
        }
        return result;
    }
    /// Process next data portion. Data passed over pipeline and store result in buffer.
    /// Params:
    /// data = input data buffer.
    /// NoCopy means we do not copy data to buffer, we keep reference
    final void put(in BufferChunk data) {
        if ( data.empty ) {
            return;
        }
        if ( pipe.empty ) {
            buffer.put(data);
            return;
        }
        try {
            auto t = process(pipe.front, [data]);
            foreach(ref p; pipe[1..$]) {
                t = process(p, t);
            }
            while(!t.empty) {
                auto b = t[0];
                buffer.put(b);
                t.popFront();
            }
            // t.each!(b => buffer.put(b));
        }
        catch (Exception e) {
            throw new DecodingException(e.msg);
        }
    }
    /// Get what was collected in internal buffer and clear it.
    /// Returns:
    /// data collected.
    final BufferChunk get() {
        if ( buffer.empty ) {
            return BufferChunk.init;
        }
        auto res = buffer.data;
        buffer = Buffer.init;
        return res;
    }
    alias getNoCopy = getChunks;
    ///
    /// get without datamove. but user receive [][]
    ///
    final immutable(BufferChunk)[] getChunks() @safe pure nothrow {
        auto res = buffer.dataChunks();
        buffer = Buffer();
        return res;
    }
    /// Test if internal buffer is empty
    /// Returns:
    /// true if internal buffer is empty (nothing to get())
    final bool empty() pure const @safe @nogc nothrow {
        return buffer.empty;
    }
    final void flush() {
        BufferChunk[] product;
        foreach(ref p; pipe) {
            product.each!(e => p.put(e));
            p.flush();
            product.length = 0;
            while( !p.empty ) product ~= p.get();
        }
        product.each!(b => buffer.put(b));
    }
}

/**
 * Processor for gzipped/compressed content.
 * Also support InputRange interface.
 */
import std.zlib;

public class Decompressor : DataPipeIface {
    private {
        Buffer       __buff;
        UnCompress   __zlib;
    }
    this() {
        __buff = Buffer();
        __zlib = new UnCompress();
    }
    final override void put(in BufferChunk data) {
        if ( __zlib is null  ) {
            __zlib = new UnCompress();
        }
        __buff.put(cast(BufferChunk)__zlib.uncompress(data));
    }
    final override BufferChunk get() pure {
        assert(__buff.length);
        // auto r = __buff.__repr.__buffer[0];
        // __buff.popFrontN(r.length);
        auto r = __buff.frontChunk();
        __buff.popFrontChunk();// = __buff._chunks[1..$];
        return cast(BufferChunk)r;
    }
    final override void flush() {
        if ( __zlib is null  ) {
            return;
        }
        auto r = __zlib.flush();
        if ( r.length ) {
            __buff.put(cast(immutable(ubyte)[])r);
        }
    }
    final override @property bool empty() const pure @safe {
        return __buff.empty;
    }
    final @property auto ref front() pure const @safe {
        debug(requests) tracef("front: buff length=%d", __buff.length);
        return __buff.front;
    }
    final @property auto popFront() pure @safe {
        debug(requests) tracef("popFront: buff length=%d", __buff.length);
        return __buff.popFront;
    }
    // final @property void popFrontN(size_t n) pure @safe {
    //     __buff.popFrontN(n);
    // }
    auto data() pure @safe @nogc nothrow {
        return __buff;
    }
}

/**
 * Unchunk chunked http responce body.
 */
public class DecodeChunked : DataPipeIface {
    //    length := 0
    //    read chunk-size, chunk-extension (if any) and CRLF
    //    while (chunk-size > 0) {
    //        read chunk-data and CRLF
    //        append chunk-data to entity-body
    //        length := length + chunk-size
    //        read chunk-size and CRLF
    //    }
    //    read entity-header
    //    while (entity-header not empty) {
    //        append entity-header to existing header fields
    //        read entity-header
    //    }
    //    Content-Length := length
    //    Remove "chunked" from Transfer-Encoding
    //

    //    Chunked-Body   = *chunk
    //                      last-chunk
    //                      trailer
    //                      CRLF
    //
    //    chunk          = chunk-size [ chunk-extension ] CRLF
    //                     chunk-data CRLF
    //                     chunk-size     = 1*HEX
    //                     last-chunk     = 1*("0") [ chunk-extension ] CRLF
    //
    //    chunk-extension= *( ";" chunk-ext-name [ "=" chunk-ext-val ] )
    //    chunk-ext-name = token
    //    chunk-ext-val  = token | quoted-string
    //    chunk-data     = chunk-size(OCTET)
    //    trailer        = *(entity-header CRLF)

    alias eType = ubyte;
    immutable eType[] CRLF = ['\r', '\n'];
    private {
        enum         States {huntingSize, huntingSeparator, receiving, trailer};
        char         state = States.huntingSize;
        size_t       chunk_size, to_receive;
        Buffer       buff;
        ubyte[]      linebuff;
    }
    final void put(in BufferChunk in_data) {
        BufferChunk data = in_data;
        while ( data.length ) {
            if ( state == States.trailer ) {
                to_receive = to_receive - min(to_receive, data.length);
                return;
            }
            if ( state == States.huntingSize ) {
                import std.ascii;
                ubyte[10] digits;
                int i;
                for(i=0;i<data.length;i++) {
                    ubyte v = data[i];
                    digits[i] = v;
                    if ( v == '\n' ) {
                        i+=1;
                        break;
                    }
                }
                linebuff ~= digits[0..i];
                if ( linebuff.length >= 80 ) {
                    throw new DecodingException("Can't find chunk size in the body");
                }
                data = data[i..$];
                if (!linebuff.canFind(CRLF)) {
                    continue;
                }
                chunk_size = linebuff.filter!isHexDigit.map!toUpper.map!"a<='9'?a-'0':a-'A'+10".reduce!"a*16+b";
                state = States.receiving;
                to_receive = chunk_size;
                if ( chunk_size == 0 ) {
                    to_receive = 2-min(2, data.length); // trailing \r\n
                    state = States.trailer;
                    return;
                }
                continue;
            }
            if ( state == States.receiving ) {
                if (to_receive > 0 ) {
                    auto can_store = min(to_receive, data.length);
                    buff.put(data[0..can_store]);
                    data = data[can_store..$];
                    to_receive -= can_store;
                    //tracef("Unchunked %d bytes from %d", can_store, chunk_size);
                    if ( to_receive == 0 ) {
                        //tracef("switch to huntig separator");
                        state = States.huntingSeparator;
                        continue;
                    }
                    continue;
                }
                assert(false);
            }
            if ( state == States.huntingSeparator ) {
                if ( data[0] == '\n' || data[0]=='\r') {
                    data = data[1..$];
                    continue;
                }
                state = States.huntingSize;
                linebuff.length = 0;
                continue;
            }
        }
    }
    final BufferChunk get() {
        // auto r = buff.__repr.__buffer[0];
        // buff.popFrontN(r.length);
        auto r = buff.frontChunk();
        buff.popFrontChunk();// = __buff._chunks[1..$];
        return cast(BufferChunk)r;
//        return r;
    }
    final void flush() {
    }
    final bool empty() {
        debug(requests) tracef("empty=%b", buff.empty);
        return buff.empty;
    }
    final bool done() {
        return state==States.trailer && to_receive==0;
    }
}

unittest {
    info("Testing Decompressor");
    globalLogLevel(LogLevel.info);
    alias eType = immutable(ubyte);
    eType[] gzipped = [
        0x1F, 0x8B, 0x08, 0x00, 0xB1, 0xA3, 0xEA, 0x56,
        0x00, 0x03, 0x4B, 0x4C, 0x4A, 0xE6, 0x4A, 0x49,
        0x4D, 0xE3, 0x02, 0x00, 0x75, 0x0B, 0xB0, 0x88,
        0x08, 0x00, 0x00, 0x00
    ]; // "abc\ndef\n"
    auto d = new Decompressor();
    d.put(gzipped[0..2]);
    d.put(gzipped[2..10]);
    d.put(gzipped[10..$]);
    d.flush();
    assert(equal(d.filter!(a => a!='b'), "ac\ndef\n"));
    auto e = new Decompressor();
    e.put(gzipped[0..10]);
    e.put(gzipped[10..$]);
    e.flush();
    assert(equal(e.filter!(a => a!='b'), "ac\ndef\n"));

    info("Testing DataPipe");
    auto dp = new DataPipe();
    dp.insert(new Decompressor());
    dp.put(gzipped[0..2]);
    dp.put(gzipped[2..$].dup);
    dp.flush();
    assert(equal(dp.get(), "abc\ndef\n"));

    info("Test unchunker properties");
    BufferChunk twoChunks = "2\r\n12\r\n2\r\n34\r\n0\r\n\r\n".dup.representation;
    BufferChunk[] result;
    auto uc = new DecodeChunked();
    uc.put(twoChunks);
    while(!uc.empty) {
        result ~= uc.get();
    }
    assert(equal(result[0], "12"));
    assert(equal(result[1], "34"));
    info("unchunker correctness - ok");
    //result[0][0] = '5';
    // assert(twoChunks[3] == '5');
    // info("unchunker zero copy - ok");
    info("Testing DataPipe - done");
}


