# Two formats that are not FOLD, and are the same format twice

Terms used here are defined in [../glossary.md](../glossary.md).

Most crease patterns in the wild are not FOLD files. FOLD dates from 2016 and
is an interchange format written by researchers; the patterns people actually
share were saved by the two desktop editors, and those have used the same two
formats for twenty years:

- **`.cp`**, written by MT777's **Orihime** and by its fork **Oriedita**. One
  crease to a line of text.
- **`.opx`**, written by Jun Mitani's **ORIPA**. The same creases, wrapped in a
  great deal of XML.

They look nothing alike and they hold exactly the same thing: a **flat list of
line segments, each with a number saying what kind of line it is**. Every
awkward part of reading one follows from that sentence, so it is worth reading
twice.

## What a `.cp` looks like

The whole format, from Oriedita's own bird base:

```
1 -200.0 -200.0 -200.0 0.0
3 200.00000000000003 -200.0 9.094947017729283E-15 9.094947017729283E-15
2 200.0 200.0 117.15728752538102 -0.0
```

A type code, then `x1 y1 x2 y2`. No header, no version, no units, no comments,
no way to write a face. An empty `.cp` is an empty file. Numbers are whatever
Java's `Double.toString` produced, which is why the second line is in
scientific notation and the third ends in a negative zero.

## What an `.opx` looks like

ORIPA is a Java program and it saves by handing its `oripa.DataSet` object to
`java.beans.XMLEncoder`, which writes out the object's fields. One crease is
seventeen lines, of which these are the first nine:

```xml
<object class="oripa.OriLineProxy">
 <void property="type">
  <int>2</int>
 </void>
 <void property="x0">
  <double>200.0</double>
 </void>
 <void property="x1">
  <double>117.15728752538102</double>
 </void>
 ...
```

Two things in that are not decoration.

**The properties are named, and they are not in point order.** `XMLEncoder`
sorts a bean's properties by name, so ORIPA writes `type`, `x0`, `x1`, `y0`,
`y1` — both `x`s, then both `y`s. Take the four numbers in the order they
appear and you get `(x0, x1)`–`(y0, y1)`, which is a perfectly plausible crease
pattern and the wrong one. Nothing in the file complains; the picture just
comes out subtly rearranged.

**A property equal to zero is not written at all.** `XMLEncoder` omits any
value that a freshly constructed bean already has, and a fresh `OriLineProxy`
is all zeroes. So a crease along the `y` axis has no `x0` and no `x1`, and an
auxiliary line — type 0 — has no `type` and is indistinguishable from an object
with no properties at all. *Absent means zero here*, which is the exact
opposite of the rule FOLD is read by, where absent means the file made no
claim. That is not a contradiction. FOLD is a format someone designed; this is
a memory dump of a Java object that happens to be readable.

There are also two dialects, because `XMLEncoder` changed how it writes a field
with no public setter. Files from 2005 say

```xml
<void property="lines">
 <array class="oripa.OriLineProxy" length="20">
```

and files from 2024 say

```xml
<void class="oripa.DataSet" method="getField">
 <string>lines</string>
 <void method="set">
  <object idref="DataSet0"/>
  <array class="oripa.OriLineProxy" length="20">
```

Neither wrapper is worth parsing. Look for `oripa.OriLineProxy` objects
wherever they are, ignore everything around them, and the two dialects become
one file.

## The type codes, and how we know

| Code | `.cp` | `.opx` |
| --- | --- | --- |
| 0 | — (refused) | auxiliary |
| 1 | the paper's edge | the paper's edge |
| 2 | mountain | mountain |
| 3 | valley | valley |
| 4 | auxiliary | — (refused) |
| 5–11 | Oriedita's further auxiliary colours | — |

The two agree on the three that matter and disagree about where auxiliary sits.
That is the kind of claim that deserves evidence, so:

**For `.cp`, Oriedita round-trips a file through FOLD and back.** Its
`CpTest.testLoadAndSaveCpFile` reads `square.cp`, converts each edge to a
`LineColor` through `FoldImporter.getColor` — mountain to `RED_1`, valley to
`BLUE_2`, flat to `CYAN_3`, everything else to `BLACK_0` — writes it out again,
and asserts the bytes are unchanged. Since the file's codes are 1, 2 and 3, the
file's code is the colour's number *plus one*: black 0 is the paper's edge and
is written 1, red is written 2, blue 3, cyan 4. `LineColor` runs on to
`GREY_10`, which is why Oriedita's auxiliary colours reach code 11.

That off-by-one is not Oriedita being odd. The four-code table is Orihime's,
and predates it; `LineColor` is numbered from zero because Java enums are, and
the two happen to be one apart.

**For `.opx`, the geometry says so.** Across the eleven ORIPA files in the
public reference corpora — Flat-Folder's `examples/original/`, and the `.opx`
test files that ship with other readers — *every* segment of type 1 lies along
the bounding rectangle of the pattern, and no segment of any other type ever
does, with one exception in a file that is plainly a syntax test. Type 1 is the
edge of the paper. The counts settle the rest: the same model saved as both
`.cp` and `.opx` has the same number of each of 1, 2 and 3 in either file.

Worth knowing: **Flat-Folder's two tables disagree with each other here.** Its
`.cp` reader maps code 1 to `B`, the edge of the paper; its `.opx` reader maps
the same code to `F`, a crease that is not folded. It gets away with it because
after tracing the faces it overwrites the assignment of every edge with only
one face on it back to `B` — so the boundary is recovered from the geometry and
the table never has to be right. A reader that does not trace faces — senbazuru,
until [#34](https://github.com/avalonalex/senbazuru/issues/34) — has nothing to
recover it from. "Another implementation does it this way" is not evidence on
its own.

## Which way is up

Both editors are Java desktop applications drawing into an AWT window, where
`y` increases *downwards*, and both store the screen coordinates unchanged.
Oriedita's `Camera.object2TV`, which is the whole of its model-to-screen
transform, translates, rotates, mirrors in `x` and scales — and never negates
`y`. So the paper is the square from `(-200, -200)` to `(200, 200)` with
`(-200, -200)` at the *top* left.

senbazuru's model space has `y` increasing upwards, so the reader negates it.
This is not a matter of taste, and it is worth being precise about why: a
crease pattern read upside down is not the same model drawn differently, it is
the **mirror image**. Reflecting a pattern and keeping every mountain a
mountain gives the reflection of what the author drew — a model that folds
perfectly well, from the other side of the paper, and is not the one in the
file. The same argument the README makes about `--rotate` turning the camera
rather than the paper.

One consequence to expect: **Oriedita's own FOLD exporter does not negate it.**
Its `.fold` files carry the screen coordinates as written, which is why its
`faces_vertices` come out clockwise when read the way FOLD's counterclockwise
convention intends. So a `.cp` read by senbazuru and the same `.cp` passed
through Oriedita's FOLD export are mirror images of each other. Ours is the one
that matches the drawing on Oriedita's screen.

## What the formats cannot say

Everything FOLD has and these do not:

| Missing | Consequence |
| --- | --- |
| Vertices | The endpoints have to be matched up by coordinate, which needs a tolerance — see `Senbazuru.Import.Segments` |
| Faces | Nothing can be folded, filled or stacked until the faces are traced from the edges |
| Fold angles | A pattern only; there is no folded form to read |
| Frames | One state of the paper, so no diagram sequence |
| Units, title, author | Nothing but geometry |

The first is not a formality. Six creases meet at the centre of Oriedita's bird
base, and the file spells that one point three different ways —
`9.094947017729283E-15 9.094947017729283E-15`, `9.094947017729283E-15 -0.0`,
and `1.2246467991473534E-14 9.094947017729283E-15` — because the editor
computed them by reflecting other points across creases and never rounded. Its
52 endpoints are 22 distinct spellings of 13 vertices. Read them as written and
the bird base is 22 disconnected pieces of a crease pattern.

The rest is why senbazuru **reads** these formats and does not write them.
Writing a `.cp` would mean silently dropping the faces, the angles and every
frame but one, which is a worse thing to do to someone's file than declining.

## References

- [ORIPA](https://github.com/oripa/oripa) — Jun Mitani's editor, and the origin
  of `.opx`. GPL-3.0: read to understand, never to copy.
- [Oriedita](https://github.com/oriedita/oriedita) (MIT) — the maintained fork
  of Orihime. `LineColor`, `CpTest` and `Camera` are the source for the `.cp`
  table and the `y` direction above; the `.cp` parser itself lives in a
  separate `fold` jar and is not in that repository.
- [Flat-Folder](https://github.com/origamimagiro/flat-folder) (MIT) — reads
  both formats, and the corpus the `.opx` check above was run over.
- [`java.beans.XMLEncoder`](https://docs.oracle.com/en/java/javase/21/docs/api/java.desktop/java/beans/XMLEncoder.html)
  — on writing only what differs from a freshly constructed instance, which is
  the whole of the missing-property rule.
