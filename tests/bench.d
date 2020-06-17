/+ dub.sdl:
    name "bench"
    dflags "-I../source"
    #debugVersions "cachetools"
    #debugVersions "nbuff"
    buildRequirements "allowWarnings"
    dependency "automem" version="*"
    dependency "ikod-containers" version="~>0"
    dependency "nbuff" version="~>0"
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
    auto r = benchmark!(f0)(1_000_000);
    writefln("append, no data copy:\n%(%s\n%)", r);
 
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
    r = benchmark!(f2)(1_000_000);
    writefln("append with data copy:\n%(%s\n%)", r);

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
    r = benchmark!(f4)(1_000_000);
    writefln("append string:\n%(%s\n%)", r);

    Nbuff nbuff;
    for(int i=0;i<100;i++)
    {
        nbuff.append("%d".format(i));
    }
    void f6()
    {
        nbuff.countUntil("10".representation);
    }
    r = benchmark!(f6)(1_000_000);
    writefln("countUntil(short):\n%(%s\n%)", r);

    void f8()
    {
        nbuff.countUntil("90919".representation);
    }
    r = benchmark!(f8)(1_000_000);
    writefln("countUntil(long) :\n%(%s\n%)", r);
    void f10()
    {
        nbuff.countUntil("90919".representation, 100);
    }
    r = benchmark!(f10)(1_000_000);
    writefln("countUntil(long,skip) :\n%(%s\n%)", r);
}

/*
Mon Dec 30 20:53:35 EET 2019
igor@igor-Zen:~/D/nbuff/tests$ ./bench 
898 ms, 237 μs, and 2 hnsecs
8 secs, 330 ms, 344 μs, and 4 hnsecs

Wed Jun 17 22:32:28 EEST 2020
$ dub --single -b release --compiler ldc2 bench.d
Running ./bench 
append, no data copy:
179 ms, 650 μs, and 7 hnsecs
append with data copy:
8 secs, 647 ms, and 289 μs
append string:
1 sec, 642 ms, and 314 μs
countUntil(short):
132 ms, 877 μs, and 6 hnsecs
countUntil(long) :
2 secs, 226 ms, 779 μs, and 3 hnsecs
countUntil(long,skip) :
1 sec, 53 ms, 47 μs, and 4 hnsecs
*/
