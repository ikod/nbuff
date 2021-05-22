<H1>Это небольшой тюториал по использованию библиотеки nbuff.</H1>

<H2>Введение</h2>

Nbuff - библиотека управления буферами. Основная цель при написании - nogc, минимальное число аллокаций, отсутствие (либо минимум) копирований данных.

Для начала - о ментальной модели, которую необходимо иметь в голове для успешного использования библиотеки.

* Nbuff - это цепочка иммутабельных буферов, плюс указатель начала данных и указатель конца данных.
* Основными операциями для Nbuff являются добавление данных (добавляются всегда после указателя конца), доступ к данным по индексу (индекс всегда от указателя начала), и освобождение обработанных данных (освобождаются всегда с указателя начала).
* Буфера, добавляемые в Nbuff берутся из (и возвращаются в) thread-local пул буферов (выделяемых через Mallocator)


Для пользователя Nbuff является "бесконечной цепочкой буферов" к которой он добавляет новые данные и отбрасывает обработанные. Всё управление памятью прозрачно для пользователя.

<H2>nogc и safe</H2>

Операции с Nbuff не используют GC. За исключением операции получения адреса буфера в памяти все операции с Nbuff являются `@safe`. Отсутствие утечек памяти и безопасное обращение к памяти обеспечивается использованием умных указателей.

<H2>Пример использования</H2>

Разберем гипотетический пример использования - чтение бинарных записей из файла, где каждая запись начинается с байта, содержащего длину данных в записи.

Дамп файла, который мы используем в примере:
<pre>
00000000  01 31|02 32 33|03 34 35  36|04 37 38 39 30|1a 61  |.1.23.456.7890.a|
00000010  62 63 64 65 66 67 68 69  6a 6b 6c 6d 6e 6f 70 71  |bcdefghijklmnopq|
00000020  72 73 74 75 76 77 78 79  7a                       |rstuvwxyz|
</pre>

Видим, что файл содержит записи:
 * длина 1, содержимое  [1]
 * длина 2, содержимое  [23]
 * длина 3, содержимое  [456]
 * длина 4, содержимое  [7890]
 * длина 26, содержимое [abcdefghijklmnopqrstuvwxyz]

Программа в цикле читает данные из файла кусочками фиксированного размера. Получив размер следующей записи в файле, мы читаем в buff до тех пор пока буфер не будет содержать всю запись. Каждый раз, когда мы обработали порцию данных (прочитали длину следующей записи или прочитали саму запись), мы вызываем pop() для освобождения обработанных данных.

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

после запуска и чтения первой порции данных из файла получаем такое состояние цепочки буферов:

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
Здесь видно что мы прочли 10 байт в буфер, позиция начала - 0, позиция конца - 10.

После получения длины первой записи (байт по смещению 0) и освобождению этого байта из буфера получаем:
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
Здесь видно, что, после освобождения одного байта, указатель начала переместился на одну позицию вправо.

Предположим что для обработки записи нам нужно иметь "непрерывное" представление данных в памяти. Это непрерывное представление создаётся вызовом buff.data(0, N), который **может потребовать сборки (копирования) только в том случае если требуемый диапазон представлен в памяти несколькими chunk-ами**. Для уменьшения числа возможных копирований увеличивайте размер буферов. Кроме того, библиотека предоставляет возможность работать с Nbuff как с range c помощью процедур из стандартной библиотеки (*не рекомендуется так как снандартные алгоритмы могут оставлять в GC-области ссылки на буфера, которые в этом случае могут не освобождаться*) и предоставляет некоторые алгоритмы позволяющие работать напрямую с разбросанными буферами.

В нашем случае вся запись помещается в одном chunk-е, поэтому в обработку попадает просто умная ссылка на этот chunk. Это видно потому что в первом байте chunk-a виден сохранившийся байт с длиной:
```
▌_beg=1 _end=2 _size=10                                                  ▐
▌00000  01▛31▟** ** ** ** ** ** ** ** ** ** ** ** ** **  .1              ▐
```

Для последней "длинной" записи получаем следующее представление:
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
Здесь видно что непрерывное представление создаётся с помощью сборки буферов в один непрерывный буфер.

В чем профит от использования библиотеки в таком простом случае?

 1. Выделение, освобождение, переиспользование памяти происходит автоматически, не загрязняя основной код.
 1. Не используется сборщик мусора, при этом гарантируется остутствие утечек памяти.
 1. Весь код, за исключением прямого доступа к памяти, является безопасным.
 1. Копирование данных происходит только когда это необходимо, и может совсем отсутствовать.

Рассмотрим другой случай - мы читаем из файла строки и обрабатываем только те, которые начинаются с подстроки "a".
Файл:
```
a short line
second line, should be filtered out
a long long long long long long long long long long line
```

Код:
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

Вывод:
```
Found [a short line]
Some line filtered out
Found [a long long long long long long long long long long line]
```

В этом случае мы совсем не собирали строки которые нас не интересуют а просто отбрасывали их, полностью избегая копирования.
