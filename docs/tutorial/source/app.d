import std.stdio;
import std.file;
import std.string;
import nbuff;
enum CHUNKSIZE = 10;

void main() @safe
{
    Nbuff buff;
    auto f = File("data.dat");
    //
    // Part 1.
    //
    byte N = 0;                     // next record length
    ulong bytes = fill(&f, &buff);  // init process
    while (bytes > 0) {
        if ( N == 0 ) {
            // We are on record boundary. First byte in the buff is record length.
            N = buff[0];                          // get first byte, this should be next record length
            buff.pop(1);                          // we processed single byte, pop it from the buff
            writefln("\nExpect %d bytes record, buff content:\n%s", N, buff.dump());
        }
        if ( N > 0 && buff.length >= N ) {        // we have complete record in the buff
            auto record = buff.data(0, N);        // smart ptr "view" into the part of original buff.
            process_record(record);
            buff.pop(record.length);              // release processed buffers
            N = 0;                                // we need next length again
            writefln("\nRecord processed, buff content:\n%s", buff.dump());
        }
        if ( (N == 0 && buff.length == 0) || (N > 0 && buff.length < N) ) {
            // we need more data from disk if we expect next 'length' but buffer is empty,
            // or buffer is too short to hold record
            writeln("Need more data");
            bytes = fill(&f, &buff);
        }
    }
    //
    // Part 2.
    // Find lines with "a" in first position without gathering buffers
    //
    writeln("=== Filter without data copy ===");
    f = File("lines.dat");
    ulong search_from = 0;
    bytes = fill(&f, &buff, false);  // init process
    while (bytes > 0) {
        auto p = buff.countUntil("\n".representation(), search_from); // search substring starting from search_from position
        if ( p >= 0 ) {
            // ok we have \n in the buffer
            if ( buff.beginsWith("a") ) {   // check if this line starts with "a"
                writefln("Found [%s]", buff.data(0, p));
            } else {
                // we have some line, scattered in several buffers and we can just throw it away
                // without processing. Note that we didn't convert it into contiguous representation
                writeln("Some line filtered out");
            }
            buff.pop(p+1);                  // throw away handled data portion
            search_from = 0;                // start next search from the beginning of current buffer
        } else {
            search_from = buff.length();    // we searched whole buffer, no need to search again
            bytes = fill(&f, &buff, false); // load more data
        }
    }
}
///
/// read next chunk of data and append it to nbuff
/// return num of attached bytes
///
auto fill(File* f, Nbuff* buff, bool dump=true) @trusted {
    auto b = Nbuff.get(CHUNKSIZE);                          // ask Nbuff for mutable memory of min length CHUNKSZIE
    auto bytes = f.rawRead(b.data()[0..CHUNKSIZE]).length;  // read data into provided buffer
    if ( bytes > 0 ) {                                      // 
        buff.append(b, bytes);                              // append what we read to buffer
        if (dump) writefln("Got %d bytes from file, buff dump:\n%s", bytes, buff.dump());
    } else {
        writeln("EOF");
    }
    return bytes;
}

void process_record(NbuffChunk record) @trusted {
    import std.algorithm;
    writefln("\nprocess record \n%s\n%(%02.2x %) [%s]", record.dump(), record.data(), record.data().map!"a.to!char");
}
