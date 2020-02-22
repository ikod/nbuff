/+ dub.sdl:
    name "bench"
    dflags "-I../source"
    #debugVersions "cachetools"
    #debugVersions "nbuff"
    buildRequirements "allowWarnings"
    dependency "automem" version="*"
    dependency "ikod-containers" version="0.0.5"
    dependency "nbuff" version="0.0.6"
+/

import std.datetime.stopwatch;
import std.stdio;
import std.algorithm;
import std.string;
import std.experimental.logger;
import std.random;
import std.range;
import nbuff;


void main()
{
    auto rnd = Random(unpredictableSeed);
    void f0()
    {
        Nbuff b;
        auto s = uniform(16, 16*1024, rnd);
        auto chunk = Nbuff.get(s);
        b.append(chunk, 3);
        chunk = Nbuff.get(2*s);
        b.append(chunk, s);
    }
    void f1()
    {
        Buffer b;
        auto s = uniform(16, 16*1024, rnd);
        b.append(new ubyte[](s));
        b.append(new ubyte[](2*s));
    }
    auto r = benchmark!(f0,f1)(1000000);
    writefln("%(%s\n%)", r);
 
    auto long_string = "A".repeat().take(2*16*1024).join();
    void f2()
    {
        Nbuff b;
        auto limit = uniform(8, 32, rnd);
        for(int i=0;i<limit;i++)
        {
            auto s = uniform(16, 16*1024, rnd);
            auto chunk = Nbuff.get(s);
            copy(long_string.representation[0..s], chunk.data);
            b.append(chunk, s);
        }
    }
    void f3()
    {
        Buffer b;
        auto limit = uniform(8, 32, rnd);
        for(int i=0;i<limit;i++)
        {
            auto s = uniform(16, 16*1024, rnd);
            auto chunk = new ubyte[](s);
            copy(long_string.representation[0..s], chunk);
            b.append(cast(immutable(ubyte)[])chunk);
        }
    }
    r = benchmark!(f2, f3)(100000);
    writefln("%(%s\n%)", r);

    void f4() @safe
    {
        Nbuff b;
        auto limit = uniform(8, 32, rnd);
        for(int i=0;i<limit;i++)
        {
            b.append("abcdef");
            if ( i % 2 )
            {
                b.pop();
            }
        }
    }
    void f5()
    {
        Buffer b;
        auto limit = uniform(8, 64, rnd);
        for(int i=0;i<limit;i++)
        {
            b.append("abcdef");
            if ( i % 2 )
            {
                b.popFront();
            }
        }
    }
    r = benchmark!(f4, f5)(1000000);
    writefln("append:\n%(%s\n%)", r);

    Nbuff nbuff;
    for(int i=0;i<100;i++)
    {
        nbuff.append("%d".format(i));
    }
    Buffer buffer;
    for(int i=0;i<100;i++)
    {
        buffer.append("%d".format(i));
    }
    void f6()
    {
        nbuff.countUntil("10".representation);
    }
    void f7()
    {
        buffer.countUntil(0, "10".representation);
    }
    r = benchmark!(f6, f7)(1000000);
    writefln("countUntil(short):\n%(%s\n%)", r);

    void f8()
    {
        nbuff.countUntil("90919".representation);
    }
    void f9()
    {
        buffer.countUntil(0, "90919".representation);
    }
    r = benchmark!(f8, f9)(1000000);
    writefln("countUntil(long) :\n%(%s\n%)", r);
    void f10()
    {
        nbuff.countUntil("90919".representation, 100);
    }
    void f11()
    {
        buffer.countUntil(100, "90919".representation);
    }
    r = benchmark!(f10, f11)(1000000);
    writefln("countUntil(long,skip) :\n%(%s\n%)", r);
}

/*
Mon Dec 30 20:53:35 EET 2019
igor@igor-Zen:~/D/nbuff/tests$ ./bench 
898 ms, 237 μs, and 2 hnsecs
8 secs, 330 ms, 344 μs, and 4 hnsecs
*/
