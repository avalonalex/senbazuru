# QuickCheck finds the bug; shrinking makes it readable

`Senbazuru.GeometrySpec` builds boxes and points with `choose`. When a property
fails, QuickCheck tries to simplify the counterexample before printing it -- but
only as well as the `shrink` function permits, and values assembled this way
shrink poorly.

The difference in practice is not subtle. Compare a reported counterexample of

    Box (V2 (-73.412) 88.107) (V2 12.998 91.043)

against

    Box (V2 0 0) (V2 1 0)

The second tells you immediately that the bug is about zero-height boxes. The
first tells you nothing at all, and you spend twenty minutes bisecting it by
hand -- which is exactly the work shrinking exists to do for you.

Writing `Arbitrary` instances with real `shrink` implementations is cheap and
pays out every single time a property fails.

Worth also knowing the alternative design. `hedgehog` ties generation and
shrinking together, so shrinking is automatic and always respects the
generator's invariants. That last part is the thing hand-written `shrink`
functions most often get wrong: they happily shrink a valid value into an
invalid one, and you chase a counterexample that could never have occurred.

## References

- Koen Claessen & John Hughes, "QuickCheck: A Lightweight Tool for Random
  Testing of Haskell Programs", *ICFP*, 2000.
- The `hedgehog` package, for integrated shrinking.
