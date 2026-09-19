-- |
-- Module      : Test.SequenceHelpers
-- Description : The two values every spec of the sequence language writes by hand.
--
-- A spec of the sequence language states what it expects as a tree written
-- out in constructors, and two pieces of that tree come up in every one: a
-- wrapper saying \"this was never text\", and a header holding nothing but
-- defaults. Each spec used to define its own, and three copies of a default
-- header are three places to update when 'Header' gains a field. Miss one,
-- and that spec goes on passing while it tests a different default from the
-- other two.
--
-- This is deliberately not "Senbazuru.Sequence.Build"'s @header@. That
-- function is one of the things under test, so an expected value built with
-- it would agree with it whatever it did. The header here is written out
-- field by field.
module Test.SequenceHelpers
  ( built,
    plainHeader,
  )
where

import Senbazuru.Sequence.Syntax

-- | A piece of the tree as a value built in Haskell carries it: with no
-- position, because it was never text.
built :: a -> Located a
built = Located NoSpan

-- | The header a sequence source gets from its one required line, @sheet@,
-- and nothing else: no title, no anchor, the coloured side up, every crease
-- flat, no closing caption. A spec that wants more says so by record update:
--
-- > (plainHeader UnitSquare) {hSide = WhiteUp}
plainHeader :: SheetSource -> Header
plainHeader sheet =
  Header
    { hTitle = Nothing,
      hSheet = built sheet,
      hAnchor = Nothing,
      hSide = ColouredUp,
      hStart = built StartFlat,
      hClosing = Nothing
    }
