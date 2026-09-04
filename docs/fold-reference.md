# What is in a FOLD file

A key-by-key reference for [FOLD 1.2](https://github.com/edemaine/FOLD/blob/main/doc/spec.md),
with what senbazuru currently does with each. For the *ideas* — what a crease
pattern is, why mountains and valleys are relative — read
[fold-primer.md](fold-primer.md) instead.

**Status** is one of: **used** (affects output), **decoded** (parsed and
available on `Frame`, nothing reads it yet), or **—** (not decoded).

## The organising principle

A `.fold` file is JSON describing a planar graph. Keys are named
`object_property`, and every such key is an array **indexed by object id**.
Ids are zero-based indices into those arrays — there is no `"id"` field
anywhere. So `edges_assignment[7]` is the assignment of edge 7, whose endpoints
are `edges_vertices[7]`.

Almost everything is optional; `{}` is a valid FOLD file. Unrecognised keys must
be ignored, and vendor extensions are namespaced with a colon (`"cpedit:page"`).

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
| `edges_foldAngle` | number[] | Degrees, `[-180, 180]`; negative is mountain | decoded |
| `edges_faces` | int[][] | Incident faces | — |
| `edges_length` | number[] | Edge length | — |

## Faces

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `faces_vertices` | int[][] | Vertices around the face, counterclockwise | decoded |
| `faces_edges` | int[][] | Edges around the face, counterclockwise | — |
| `faces_faces` | int[][] | Adjacent faces, may contain nulls | — |

Counterclockwise winding is what defines a face's normal direction, and
therefore which side is "up".

## Layer ordering

| Key | Type | Meaning | Status |
| --- | --- | --- | --- |
| `faceOrders` | [int, int, int][] | `[f, g, s]`: face `f` is above (`+1`), below (`-1`), or unordered (`0`) relative to `g` | — |
| `edgeOrders` | [int, int, int][] | Same, for edges, 2D only | — |

See [notes/layer-ordering.md](notes/layer-ordering.md) for why this is stored
rather than computed.

## What FOLD does **not** contain

Worth stating plainly, because the absences are easy to assume away.

- **No arrows, operations, or step captions.** There is no key anywhere in the
  spec describing the *transition* between two frames. A multi-frame file is a
  flipbook of states, not an instruction manual. Arrows must be inferred by
  diffing consecutive frames for creases whose `edges_foldAngle` changed.
- **No folding sequence semantics beyond array order.** `file_classes:
  ["diagrams"]` declares intent — *"a sequence of frames representing folding
  steps"* — and `file_frames[i]` is frame `i+1`. That is the whole of it.
- **No layer ordering unless supplied.** `faceOrders` is data the file carries
  because recomputing it is hard, not a derived convenience.
- **No units on the geometry itself.** `frame_unit` labels the whole frame;
  individual coordinates are bare numbers.

## A caveat before building on the sequence half

Every example in the reference repository — `box`, `diagonal-cp`,
`diagonal-folded`, `simple`, `squaretwist` — is **single-frame**. The
multi-frame half of the format has essentially no published test data, so
anything we build on it needs fixtures we author ourselves, and we will be
deciding what correct looks like.
