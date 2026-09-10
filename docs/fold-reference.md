# What is in a FOLD file

A key-by-key reference for [FOLD 1.2](https://github.com/edemaine/FOLD/blob/main/doc/spec.md),
with what senbazuru currently does with each. For the *ideas* — what a crease
pattern is, why mountains and valleys are relative — read
[fold-primer.md](fold-primer.md) instead.

**Status** is one of: **used** (affects output), **decoded** (parsed and
available on `Frame`, nothing reads it yet), or **—** (not decoded).

Status describes *reading*. Writing is simpler: **every key survives**, whatever
its status — see [Writing a file back out](#writing-a-file-back-out).

## The organising principle

A `.fold` file is JSON describing a planar graph. Keys are named
`object_property`, and every such key is an array **indexed by object id**.
Ids are zero-based indices into those arrays — there is no `"id"` field
anywhere. So `edges_assignment[7]` is the assignment of edge 7, whose endpoints
are `edges_vertices[7]`.

Almost everything is optional; `{}` is a valid FOLD file. Unrecognised keys must
not be choked on, and vendor extensions are namespaced with a colon
(`"cpedit:page"`). senbazuru does not interpret them, but it does keep them.

## File metadata

Top level only. Note `file_spec` is a **number**, not an integer — real files
say `1.1`.

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `file_spec` | number | Spec version | used |
| `file_creator` | string | Creating software | used |
| `file_author` | string | Human author | decoded |
| `file_title` | string | Title | used |
| `file_description` | string | Description | decoded |
| `file_classes` | string[] | `singleModel`, `multiModel`, `animation`, `diagrams` | used |
| `file_frames` | object[] | Frames after the key frame | used |

## Frame metadata

The top-level object is **both** the file metadata **and** the first frame (the
"key frame"). Frames after it live in `file_frames`.

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `frame_author` | string | | decoded |
| `frame_title` | string | | used (SVG `<title>`) |
| `frame_description` | string | | decoded |
| `frame_classes` | string[] | `creasePattern`, `foldedForm`, `graph`, `linkage` | used |
| `frame_attributes` | string[] | `2D`, `3D`, `manifold`, `orientable`, `selfTouching`, … | decoded |
| `frame_unit` | string | `unit`, `in`, `pt`, `m`, `cm`, `mm`, `um`, `nm` | decoded |
| `frame_parent` | integer | Parent frame id | decoded |
| `frame_inherit` | boolean | Inherit unset properties from the parent | decoded |

`frame_parent` / `frame_inherit` form a **tree for data reuse**. They are not
the sequence — order comes from the `file_frames` array. Inheritance is decoded
but not resolved.

## Vertices

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `vertices_coords` | number[][] | `[x, y]` or `[x, y, z]` | used |
| `vertices_vertices` | int[][] | Adjacent vertices, **counterclockwise** | — |
| `vertices_edges` | int[][] | Incident edges | — |
| `vertices_faces` | int[][] | Incident faces, may contain nulls | — |

The counterclockwise guarantee on `vertices_vertices` is exactly the rotational
order a half-edge structure needs — see
[notes/half-edge.md](notes/half-edge.md).

## Edges

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `edges_vertices` | [int, int][] | The two endpoints | used |
| `edges_assignment` | string[] | `B` `M` `V` `F` `U` `C` `J` | used |
| `edges_foldAngle` | number[] | Degrees, `[-180, 180]`; negative is mountain | used |
| `edges_faces` | int[][] | Incident faces | — |
| `edges_length` | number[] | Edge length | — |

## Faces

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `faces_vertices` | int[][] | Vertices around the face, counterclockwise | used |
| `faces_edges` | int[][] | Edges around the face, counterclockwise | — |
| `faces_faces` | int[][] | Adjacent faces, may contain nulls | — |

Counterclockwise winding is what defines a face's normal direction, and
therefore which side is "up".

Faces of a crease pattern are filled with the paper colour, all of them in one
area since they abut and never overlap.

A folded form takes one of two routes. Folded flat, it is drawn as what can be
*seen* of it — each face cut down to the part no nearer layer covers, each edge
kept only where the paper differs across it, and the two sides of the sheet in
different colours; `Senbazuru.Origami.Visible` works that out from a
`faceOrders`, its own or one `Senbazuru.Origami.Stacking` solved. With paper
still in the air it is filled face by face in the order the `faceOrders` gives,
every crease drawn over the top, and with no `faceOrders` at all it stays a
wireframe. `--no-fill` turns filling off entirely and draws every crease, which
is the escape hatch for a file none of this can make sense of.

Note that senbazuru does **not** trust the stated winding for filling, and does
not need to: a simple closed polygon covers the same region whichever way round
its corners are listed, and real files disagree with the spec often enough that
relying on it would be a bug waiting to happen. Folding works the orientation
out from the coordinates for the same reason.

`faceOrders` is the exception, and the reason is worth knowing. Its `s` is read
against a face's **normal**, which is *defined* by that face's winding — so the
signs and the windings in a file were written against each other. A file with
backwards windings has backwards normals and backwards signs, and the two
cancel; recomputing the winding would uncancel them and turn the model
inside out. Here the file's winding is taken exactly as written — by everything
that *reads* a frame.

Folding is the exception, because it rewrites the winding on purpose: it needs
the true one to decide which way each fold turns, and writes it out so the
result is a frame whose winding can be trusted. Having moved the winding it
moves the signs with it, swapping `Above` and `Below` on every entry whose
**second** face was turned round, so that the file still says what it said.

## Layer ordering

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `faceOrders` | [int, int, int][] | `[f, g, s]`: face `f` is above (`+1`), below (`-1`), or unordered (`0`) relative to `g` | used; computed for flat-folded frames that lack it |
| `edgeOrders` | [int, int, int][] | Same, for edges, 2D only | — |

See [notes/layer-ordering.md](notes/layer-ordering.md) for why this is stored
rather than left to the reader, and [notes/taco-taco.md](notes/taco-taco.md)
for how it is computed when a flat-folded frame arrives without it.

## Writing a file back out

senbazuru can write FOLD as well as read it: `Senbazuru.Fold.Load` has
`encodeFoldFile` and `saveFoldFile` against its `decodeFoldFile` and
`loadFoldFile`. Three decisions are worth stating, because each of them could
plausibly have gone the other way.

**Nothing is dropped.** Every key above comes back out, including the ones
marked **—** and including vendor extensions. Keys the decoder does not
understand are collected verbatim into `Frame`'s `frameExtras` and written back
where they came from — a file's `"cpedit:page"` survives a trip through
senbazuru, and so does its `vertices_edges`. Destroying another tool's data
because we have not implemented that part of the specification yet is not a
service to anyone, and FOLD namespaces vendor keys precisely so they can
survive a tool that does not read them.

**A field that was absent stays absent.** The decoder is permissive and reports
a missing `faces_vertices` as an empty list, but writing `[]` back would tell
the next reader that this model records no faces, which is a different claim
from not mentioning them. So a `Nothing`, an empty list, and a `frame_inherit`
of `false` are simply not written. `{}` in gives `{}` out.

**Keys come out in the order this page lists them**, with each frame's unknown
keys sorted after its known ones, and the output is compact. That makes the
bytes reproducible and a diff between two files readable.

The one thing that *does* drop a key is folding. `foldFrame` rewrites every
coordinate and reverses the winding of any face that ends up turned over, so a
carried `faces_edges` — which lists a face's edges in the order of its corners
— would no longer be true, and `"cpedit:page"` describes a crease pattern that
this no longer is. It keeps none of them rather than write something false.

A round trip is therefore a fixed point on the decoded document — tested on
every `.fold` file in `test/fixtures/`, which are copies of the ones in
`examples/` — but not on the bytes: whitespace goes, `"m"` becomes `"M"`, and
numbers are reformatted. [notes/round-trips.md](notes/round-trips.md) has the
full list, the reasoning, and the one case the writer still gets wrong.

## What FOLD does **not** contain

Worth stating plainly, because the absences are easy to assume away.

- **No arrows, operations, or step captions.** There is no key anywhere in the
  spec describing the *transition* between two frames. A multi-frame file is a
  flipbook of states, not an instruction manual, so an arrow has to be inferred
  by diffing consecutive frames — which senbazuru does, in
  `Senbazuru.Origami.Step`. Note it compares **positions** rather than
  `edges_foldAngle`: a frame may record no angles, may record angles that
  disagree with its own coordinates, and a step may move paper without changing
  an angle at all by turning the model over. The coordinates are what the
  reader is looking at.
- **No folding sequence semantics beyond array order.** `file_classes:
  ["diagrams"]` declares intent — *"a sequence of frames representing folding
  steps"* — and `file_frames[i]` is frame `i+1`. That is the whole of it. Nor
  could a tool derive the steps for you: see
  [notes/no-sequence-solver.md](notes/no-sequence-solver.md).
- **No layer ordering unless supplied.** `faceOrders` is data the file carries
  because recomputing it is hard in general, not a derived convenience.
  senbazuru recomputes it for flat-folded frames all the same, because a folded
  form it computed itself has nowhere else to get one.
- **No units on the geometry itself.** `frame_unit` labels the whole frame;
  individual coordinates are bare numbers.

## A caveat before building on the sequence half

Every example in the reference FOLD repository — `box`, `diagonal-cp`,
`diagonal-folded`, `simple`, `squaretwist` — is **single-frame**, so nothing we
can vendor exercises `file_frames` at all.

Multi-frame files do exist elsewhere, including one with 33 frames, but the
substantial collections are GPL-licensed and therefore off-limits to this
MIT-licensed repo — see the third-party rules in `AGENTS.md`. They are useful
for *checking understanding*, not for copying.

So `examples/quarter-fold-steps.fold` is ours, and it is the only multi-frame
file here. Its folded coordinates were computed by senbazuru's own folding
rather than typed out, which is how a sequence can be authored at all without a
FOLD writer: fold the same crease pattern to each step's angles and record where
the paper landed. Each frame repeats the whole graph, because `frame_inherit` is
decoded and not resolved.

So multi-frame support needs fixtures we author ourselves.
