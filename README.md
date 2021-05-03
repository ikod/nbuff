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


Usage scenario:
You are reading bulk newline delimited lines (or any other way structured data) from TCP socket and process it as soon as possible. Every time you received something like:

```line1\nline2\nli``` <- note incomplete last line.

from network to your socket buffer you can process 'line1' and 'line2' and then you have keep whole buffer (or copy 
and save it incomplete part 'li') just because you have some incomplete data.

This leads to unnecessary allocations and data movement (if you choose to free old buffer and save incomplete part)
or memory wasting (if you choose to preallocate very large buffer and keep processed and incomplete data).

Nbuff solve this problem by using memory pool and smart pointers - it take memory chunks from pool for reading
from network(file, etc...), and authomatically return buffer to pool as soon as you processed all data in it and moved
'processed' pointer forward.
 
So Nbuff looks like some "window" on the list of buffers, filled with network data, and as soon as buffer moves out of this
window and dereferenced it will be automatically returned to memory pool. Please note - there is no GC allocations, everything
is done usin malloc.

Here is sample of buffer lifecycle (see code or docs for exact function signatures):
1. Nbuff nbuff; - initialize nbuff structure.
1. buffer = Nbuff.get(bsize) - gives you non-copyable mutable buffer of size >= bsize
1. socket.read(buffer.data) - fill buffer with network data.
1. nbuff.append(buffer) - convert mutable non-copyable buffer to immutable shareable buffer and append it to nbuff
valuable_data = nbuff.data(0, 100); - get immutable view to first 100 bytes of nbuff (they can be non-continous)
1. nbuff.pop(100) - release fist 100 bytes of nbuff, marking them as "processed".
 If there are any previously appended buffers which become unreferenced at this point, then they will be
 returned to the pool.
1. When nbuff goes out of scope all its buffers will be returned to pool.

You can find some examples in unittest section of buffer.d 

