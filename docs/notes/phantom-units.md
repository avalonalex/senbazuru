# Making the unit rule a type error

`Senbazuru.Diagram` carries a rule enforced entirely by prose:

> Shape coordinates are in model units. Stroke widths are in page units and are
> never scaled.

Nothing stops you adding a stroke width to an x-coordinate. Both are `Double`.
A phantom type parameter would stop you:

```haskell
data Space = Model | Page

newtype V2 (s :: Space) = V2 { v2x :: Double, v2y :: Double }

applyTransform :: Transform -> V2 'Model -> V2 'Page
```

The parameter `s` appears in the type and never in any value -- hence "phantom".
It costs nothing at runtime, it erases completely, and it makes the mixing
mistake unrepresentable rather than merely discouraged. The signature of
`applyTransform` also stops needing a comment: it says what it does.

The interesting question is not *how* but *whether*. Every function gains a
parameter, type errors get longer, and genuinely polymorphic helpers need an
explicit `forall s.`. This codebase is a good place to find out where that line
sits, because the rule is real, already written down, and currently relies on
whoever is reading remembering it.

## References

- Andrew Kennedy, "Types for Units-of-Measure: Theory and Practice", *CEFP*,
  2009 -- the design that made this mainstream, in F#.
- Takayuki Muranushi & Richard Eisenberg, "Experience Report: Type-checking
  Polymorphic Units for Astrophysics Research in Haskell", *Haskell Symposium*,
  2014.
- The `units` package on Hackage, for how far this idea can be pushed.
