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

import nbuff;


void main()
{
    auto rnd = Random(unpredictableSeed);
    void f0()
    {
        Nbuff b;
        auto s = uniform(16, 16*1024, rnd);
        auto chunk = Nbuff.get(s);
        //copy("Abc".representation, chunk.data);
        b.append(chunk, 3);
        // chunk = Nbuff.get(16);
        // copy("Def".representation, chunk.data);
        // b.append(move(chunk), 3);
    }
    void f1()
    {
        Buffer b;
        auto s = uniform(16, 16*1024, rnd);
        b.append(new ubyte[](s));
        //b.append("Def");
    }
    auto r = benchmark!(f0,f1)(10000000);
    writefln("%(%s\n%)", r);
}

/*
Mon Dec 30 20:53:35 EET 2019
igor@igor-Zen:~/D/nbuff/tests$ ./bench 
898 ms, 237 μs, and 2 hnsecs
8 secs, 330 ms, 344 μs, and 4 hnsecs
*/