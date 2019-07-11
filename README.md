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

