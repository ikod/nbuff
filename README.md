## Nbuff ##

Nbuff is `nogc` buffer. Goals:

* give user immutable view on bytes
* avoid data copy
* avoid GC-allocations

Main consumer of Nbuff can be networking code. Usage scenario: user requested mutable ubyte[] from Nbuff, read data from network into this buffer, then append received data to Nbuff. Then you can find patterns in Nbuff content, apply range algorithms to it, split in on parts, as Nbuff behave as range of bytes - everything without data copy and memory allocations.

All Nbuff content is refcounted, so it will be authomatically freed if not referenced.

Code sample:

```
    NbuffChunk receiveData(int socket, size_t n) @safe
    {
        // Nbuff.get() - get unique reference for n mutable bytes
        // You can't have multiple references to this buffer (this is unique_ptr)
        auto buffer = Nbuff.get(n);

        // now read data from socket to buffer - unsafe as you pet pointer to buffer 
        auto rc = () @trusted {
            return .recv(socket, cast(void*)&buffer.data[ptr], n, 0);
        }();

        if ( rc > 0 )
        {
            // if we received something - convert it to immutable buffer and return
            return NbuffChunk(buffer, rc);
        }
        else
        {
            throw Exception("");
        }
        // if you didn't attached "buffer" to anything - it will be freed on leaving scope
    }
    void readReply(int socket, size_t n)
    {
        Nbuff b;
        try
        {
            NbuffChunk r = receiveData(socket, n);
            b.append(r);
        }
        catch (Exception e)
        {
            // done
        }
    }
```

## Memory buffer. ##

The main goal of this package is to **minimize data movement when receiving from network and allow standard algorithms on received data**.


Basically buffer is immutable(immutable(ubyte)[])[], but it support some useful Range properties, it

    isInputRange!Buffer,
    isForwardRange!Buffer,
    hasLength!Buffer,
    hasSlicing!Buffer,
    isBidirectionalRange!Buffer,
    isRandomAccessRange!Buffer

so it can be used with many range algorithms, but it supports several optimized methods like `find`,
`indexOf`, `splitOn`, `findSplitOn`.

For example:
```
    Buffer httpMessage = Buffer();
    httpMessage.append("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r");
    httpMessage.append("\n");
    httpMessage.append("Conte");
    httpMessage.append("nt-Length: 4\r\n");
    httpMessage.append("\r\n");
    httpMessage.append("body");
    writeln(httpMessage.splitOn('\n').map!"a.toString.strip");
```
prints:
```
["HTTP/1.1 200 OK", "Content-Type: text/plain", "Content-Length: 4", "", "body"]
```
At the same time:

 * typeid(httpMessage.splitOn('\n')) - optimized, returns Buffer[]
 * typeid(httpMessage.split('\n')) - from std.algorithms, returns Buffer[]
 * typeid(httpMessage.splitter('\n')) - from std.algorithms, returns lazy Result

will give same results.

You can find examples in unittest section of buffer.d 
Buffer supports zero-copy (in most cases) append, split, slice, popFront and popBack, as long as some useful range primitives - find, indexOf, etc.

