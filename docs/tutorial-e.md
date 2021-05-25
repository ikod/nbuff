<H1> This is a small tutorial for the nbuff library. </H1>

<H2> Introduction </h2>

Nbuff is a buffer management library. The main goal when writing it was: @nogc, @safe, minimum number of allocations, the absence of (or minimal) data copying.

First about the mental model you need to have in mind for the successful use of the library.

* Nbuff is a chain of immutable buffers, plus pointers (indexes) to data start and end.
* The main operations for Nbuff are appending data (always after the end pointer), accessing the data by index (the index is always from the start pointer), and freeing the processed data (always freed from the start pointer).
* Buffers added to Nbuff are taken from (and returned to) a thread-local buffer pool (allocated via Mallocator)


For the library user, Nbuff is an "infinite chain of buffers" to which he adds new data and discards the processed data. All memory management is transparent to the user.

<H2> nogc and safe </H2>

Nbuff operations do not use GC. Except for the operation of obtaining the address of a buffer in memory, all operations on Nbuff are `@safe`. No memory leaks and safe memory access is ensured by the use of smart pointers.

<H2> Usage Example </H2>

Let's analyze a hypothetical example of use - reading binary records from a file, where each record begins with a byte containing the length of the data in the record.

The dump of the file we are using in the example:
<pre>
00000000  01 31|02 32 33|03 34 35  36|04 37 38 39 30|1a 61  |.1.23.456.7890.a|
00000010  62 63 64 65 66 67 68 69  6a 6b 6c 6d 6e 6f 70 71  |bcdefghijklmnopq|
00000020  72 73 74 75 76 77 78 79  7a                       |rstuvwxyz|
</pre>

We see that the file contains records:
 * length 1, content [1]
 * length 2, content [23]
 * length 3, content [456]
 * length 4, content [7890]
 * length 26, content [abcdefghijklmnopqrstuvwxyz]

The program reads data from the file in pieces of a fixed size. After we received the size of the next record in the file, we read from file into memory chunks and attach them to buff until the buffer contains the entire record. Every time we processed some data (read the length of the next record or read the record itself), we call pop () to release the processed data.

```d
import std.stdio;
import std.file;
import nbuff;
enum CHUNKSIZE = 10;

void main() @safe
{
    Nbuff buff;
    auto f = File("data.dat");
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
}
///
/// read next chunk of data and append it to nbuff
/// return num of attached bytes
///
auto fill(File* f, Nbuff* buff) @trusted {
    auto b = Nbuff.get(CHUNKSIZE);                          // ask Nbuff for mutable memory of min length CHUNKSZIE
    auto bytes = f.rawRead(b.data()[0..CHUNKSIZE]).length;  // read data into provided buffer
    if ( bytes > 0 ) {                                      // 
        buff.append(b, bytes);                              // append what we read to buffer
        writefln("Got %d bytes from file, buff dump:\n%s", bytes, buff.dump());
    } else {
        writeln("EOF");
    }
    return bytes;
}

void process_record(NbuffChunk record) @trusted {
    import std.algorithm;
    writefln("\nprocess record \n%s\n%(%02.2x %) [%s]", record.dump(), record.data(), record.data().map!"a.to!char");
}
```

after starting and reading the first piece of data from the file, we get the following state of the buffer chain:

```
▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜
▌_length   = 10                                                          ▐
▌_begIndex = 0                                                           ▐
▌_endIndex = 1                                                           ▐
▌chunk 0                                                                 ▐
▌_beg=0 _end=10 _size=10                                                 ▐
▌00000 ▛01 31 02 32 33 03 34 35 36 04▟** ** ** ** ** **   .1.23.456.     ▐
▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟
```
Here you can see that we have read 10 bytes into the buffer, the start position is 0, the end position is 10.

After getting the length of the first record (byte at offset 0) and freeing this byte from the buffer, we get:
```
▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜
▌_length   = 9                                                           ▐
▌_begIndex = 0                                                           ▐
▌_endIndex = 1                                                           ▐
▌chunk 0                                                                 ▐
▌_beg=1 _end=10 _size=10                                                 ▐
▌00000  01▛31 02 32 33 03 34 35 36 04▟** ** ** ** ** **  .1.23.456.      ▐
▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟
```

Here you can see that, after freeing one byte, the start pointer has moved one position to the right.

Suppose we need to have a "continuous" representation of the data in memory to process a record. This contiguous view is created by a call to buff.data (0, N), which ** may require assembly (copying) only if the required range is represented in memory by several chunks **. Increase the size of the buffers to reduce the number of possible copies. In addition, the library provides the ability to work with Nbuff as with range using procedures from the standard library (* not recommended since standard algorithms can leave references to buffers in the GC area, which in this case may not be freed *) and provides some algorithms that allow work directly with scattered buffers.

In our case, the entire record is placed in one chunk, so just a smart link to this chunk is processed. This can be seen because in the first byte of chunk-a you can see the remaining byte with the length:
```
▌_beg=1 _end=2 _size=10                                                  ▐
▌00000  01▛31▟** ** ** ** ** ** ** ** ** ** ** ** ** **  .1              ▐
```

For the last "long" record we get the following representation:
```
▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜
▌_length   = 26                                                          ▐
▌_begIndex = 0                                                           ▐
▌_endIndex = 4                                                           ▐
▌chunk 0                                                                 ▐
▌_beg=5 _end=10 _size=10                                                 ▐
▌00000  37 38 39 30 1a▛61 62 63 64 65▟** ** ** ** ** **   7890.abcde     ▐
▌chunk 1                                                                 ▐
▌_beg=0 _end=10 _size=10                                                 ▐
▌00000 ▛66 67 68 69 6a 6b 6c 6d 6e 6f▟** ** ** ** ** **   fghijklmno     ▐
▌chunk 2                                                                 ▐
▌_beg=0 _end=10 _size=10                                                 ▐
▌00000 ▛70 71 72 73 74 75 76 77 78 79▟** ** ** ** ** **   pqrstuvwxy     ▐
▌chunk 3                                                                 ▐
▌_beg=0 _end=1 _size=10                                                  ▐
▌00000 ▛7a▟** ** ** ** ** ** ** ** ** ** ** ** ** ** **   z              ▐
▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟

process record 
▌_beg=0 _end=26 _size=26                                                 ▐
▌00000 ▛61 62 63 64 65 66 67 68 69 6a 6b 6c 6d 6e 6f 70  abcdefghijklmnop▐
▌00016  71 72 73 74 75 76 77 78 79 7a▟** ** ** ** ** **  qrstuvwxyz      ▐
```
Here you can see that the contiguous view is created by assembling (copying) the buffers into one (new) contiguous buffer.

What is the profit from using the library in such a simple case?

 1. Allocation, release, reuse of memory occurs automatically, without polluting the main code.
 1. The garbage collector is not used, while the absence of memory leaks is guaranteed.
 1. All code, except for direct memory access, is safe.
 1. Data copying occurs only when it is necessary, and may not be required at all.

Consider another case - we read lines from a file and process only those that start with the substring "a".
File:

```
a short line
second line, should be filtered out
a long long long long long long long long long long line
```

The code:
```d
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

```

Output:
```
Found [a short line]
Some line filtered out
Found [a long long long long long long long long long long line]
```

In this case, we did not collect lines that we were not interested in at all, we simply discard them, completely avoiding copying.
