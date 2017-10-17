## Memory buffer. ##

Basically buffer is immutable(immutable(ubyte)[])[], but it support some useful Range properties.

The main goal to have Buffer is to **minimize data movement when receiving or sending data from/to network**.

Buffer supports zero-copy (in most cases) append, split, slice, popFront and popBack, as long as some useful range primitives - find, indexOf, etc.

It allows safe transformation of data received from network without unneccesary data copy.
For example you can easily split received HTTP response on `headers` Buffer and `body` Buffer, then apply any transformations oh headers and body.

Here is some examples.

```d
    auto b = Buffer();
    b.append("abc");
    b.append("def".representation);
    b.append("123");

```

In memory this buffer looks like
```d

        | _pos
        v
  +---+---------+
  | 0 | "abc"   |
  +---+---------+
  | 1 | "def"   |
  +---+---------+
  | 2 | "123"   |
  +---+---------+
            ^
            | _end_pos

```

now let we append one more chunk "456" to Buffer b
```d

        | _pos
        v
  +---+---------+
  | 0 | "abc"   |
  +---+---------+
  | 1 | "def"   |
  +---+---------+
  | 2 | "123"   |
  +---+---------+
  | 3 | "456"   |
  +---+---------+
            ^
            | _end_pos

```
Let split b on '2', then we will have two buffers:

```d

        | _pos                            | _pos
        v                                 v
  +---+---------+                +---+---------+
  | 0 | "abc"   |                | 0 | "123"   |
  +---+---------+                +---+---------+
  | 1 | "def"   |                | 1 | "456"   |
  +---+---------+                +---+---------+
  | 2 | "123"   |                          ^
  +---+---------+                          | _end_pos
          ^
          | _end_pos

```
So we have two separate Buffers without any data copy.

popFront and popBack just move _pos and _end_pos. If any of data chunks become unreferenced, then we just pop this chunk, so it can be garbage collected. 
b.popFrontN(4) will give us

```d
        | _pos
        v
  +---+---------+             | _pos
  | 0 | "abc"   |             v
  +---+---------+     +---+---------+
  | 1 | "def"   |     | 0 | "def    |
  +---+---------+     +---+---------+
  | 2 | "123"   |     | 1 | "123"   |
  +---+---------+     +---+---------+
  | 3 | "456"   |     | 2 | "456"   |
  +---+---------+     +---+---------+
            ^                   ^
            | _end_pos          | _end_pos
```

Chunk "abc" become unreferenced and can be collected by GC.

Similarly works popBack/popBackN.

Buffer supports next properties

    isInputRange!Buffer,
    isForwardRange!Buffer,
    hasLength!Buffer,
    hasSlicing!Buffer,
    isBidirectionalRange!Buffer,
    isRandomAccessRange!Buffer

so it can be used with a lot of range algorithms, but it supports several optimized methods like `find`,
`indexOf`.

You can find exemples in unittest section of buffer.d