# A round trip only tests what the decoder kept

Terms used here are defined in [../glossary.md](../glossary.md).

senbazuru reads FOLD files, and for a long time nothing wrote them. The first
test anyone reaches for when a writer arrives is the **round trip**: read a
file, write it out again, read the result, and check that nothing changed.

```haskell
decodeFoldFile (encodeFoldFile x) === Right x
```

It is a good test. It is also a trap, and the trap is worth seeing before you
fall into it, because the failing version and the passing version look
identical.

## The trap

That property compares two *decoded values*. It says nothing whatsoever about
the parts of the file the decoder never turned into one.

`examples/diagonal-cp.fold` is 703 bytes and thirteen top-level keys. senbazuru
understands ten of them. The other three are:

```json
"cpedit:page":    {"xMin": 0, "yMin": 0, "xMax": 1, "yMax": 1},
"vertices_edges": [[0, 3], [1, 4, 0], [1, 2], [3, 4, 2]],
"faces_edges":    [[0, 4, 3], [1, 2, 4]]
```

The first is a vendor extension — the editor that wrote the file remembering
its page bounds. The other two are ordinary FOLD, listed in the specification;
we simply have not implemented them.

Now suppose the decoder drops all three, as ours did, and the writer therefore
never sees them. The round trip **passes**. It passes for every file, on every
key, forever, because the value being compared has already had the interesting
part removed. What looks like evidence that the decoder is complete is only
evidence that it is self-consistent — and a decoder that reads `{}` from every
file and writes `{}` back passes it perfectly.

## The fix is a field

Give the leftovers somewhere to live. senbazuru's `Frame` has

```haskell
frameExtras :: !Object
```

which is every key of the frame's JSON object that the decoder did not claim,
kept exactly as it arrived and written back where it came from. The round trip
now compares a value that contains the bytes' whole content, so it means what
it appeared to mean all along.

This is the same move a compiler makes when it wants a formatter. A parser
built only to compile can throw away comments and whitespace, because the
compiler does not need them; the moment something wants to *print the source
back*, that "trivia" has to be somewhere in the tree. rust-analyzer calls the
result **lossless**; Roslyn calls it **full fidelity**. Same idea, and the same
reason.

## What it costs

Keeping what you do not understand moves a responsibility rather than removing
one. The writer can no longer be the thing that decides a key is wrong, because
it has no idea what any of them mean — so whatever *transforms* the document has
to.

`Senbazuru.Origami.Folding.foldFrame` is the one transform senbazuru has, and it
drops `frameExtras` entirely. Folding rewrites every coordinate and reverses the
winding of any face that ends up turned over. `faces_edges` lists a face's edges
in the same order as its corners, so it does not survive that; `cpedit:page` is
a crease pattern's page, and the result is not a crease pattern. Writing either
one out again would be stating something we have reason to believe is false,
which is a worse outcome than losing it.

The rule that falls out: **preserve at the boundary, discard at the transform.**
The boundary cannot judge; the transform is the only thing that knows what it
broke.

## What the round trip still does not prove

Even with nothing dropped, a fixed point on the decoded value is not equality of
bytes. senbazuru's output differs from its input in these ways, all of them
known:

| Difference | Why |
| --- | --- |
| Whitespace removed, keys reordered into specification order | Reproducible output, readable diffs |
| `"m"` written back as `"M"` | The spec's codes are uppercase; the decoder accepts either |
| `1.0` written as `1`, `1e2` as `100` | Whatever the JSON encoder considers shortest |
| `-0.0` written as `0` | See below |
| `"faces_vertices": []` and `"file_title": null` become absent | An empty array we invented is a claim the file did not make, and neither is a `null` |
| A key written twice keeps its **first** value | JSON says nothing about duplicates; measured, ours takes the first |

703 bytes in, 478 out, same document. If you need the bytes back exactly, a
round trip on values is not the test you want — but that is a much rarer
requirement than it sounds, and paying for it means keeping the input text.

The negative zero is worth a second look, because the reason is not the one you
would guess and it is load-bearing. Reading a `-0.0` out of a file loses the
sign on its own: JSON numbers arrive as `Scientific`, whose coefficient is an
`Integer`, which has no sign to keep. But the negative zeros that actually
matter are not read, they are *computed* — folding produces them, exactly as it
does for the SVG backend, where `formatNumber` has to normalise them so golden
files stay stable. Those survive into a `Frame`, and they come out as `0` only
because the encoder builds a list of `(Key, Value)` pairs, and `toJSON` of a
`Double` rounds through `Scientific` on the way in. Encoding a `Double`
*directly* does not:

```
encode          (-0.0 :: Double)   ==  "-0.0"
encode (toJSON  (-0.0 :: Double))  ==  "0"
```

So the obvious optimisation — build the `Series` straight from `toEncoding` and
skip the intermediate `Value` — would quietly put negative zeros back into
written files. There is a test pinning it for that reason.

## One thing that is still wrong

A `Double` that is not finite has no JSON number to be written as, and the
encoder does not notice. `aeson` writes infinities as *strings* and `NaN` as
`null`:

```json
{"vertices_coords": [["+inf", null, "-inf"]]}
```

which is not FOLD, and no other reader will take it. It is hard to reach —
nothing in senbazuru produces a non-finite coordinate today — but the decoder
will happily read a `null` coordinate back as `NaN`, so the two halves agree
with each other and with nobody else. The honest fix is for the encoder to
refuse, which means `encodeFoldFile` returning `Either` the way every other
fallible thing in this codebase does. It has not been done yet.

## References

- [FOLD specification](https://github.com/edemaine/FOLD/blob/main/doc/spec.md) —
  on unrecognised keys, and on the `vendor:key` convention for extensions.
- [Roslyn's syntax trees](https://github.com/dotnet/roslyn/blob/main/docs/wiki/Roslyn-Overview.md#syntax-trees)
  and [rust-analyzer's syntax notes](https://github.com/rust-lang/rust-analyzer/blob/master/docs/book/src/contributing/syntax.md)
  — the same problem in a compiler, and the same answer.
