-- |
-- Module      : Test.SequenceHelpers
-- Description : The values and walks several specs of the sequence language need.
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
--
-- Two more things are here for the first reason, that copies drift. Specs of
-- the checker and of the passes after it share a short source to write
-- moves into, and a walk over every move of a sequence; two copies of
-- \"every move\" are two chances to disagree about what is inside a block.
module Test.SequenceHelpers
  ( built,
    plainHeader,
    sourceOf,
    allMoves,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
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

-- | A source with a plain square sheet and these lines after its header. The
-- lines start on line 3, which is what a test of a span counts from.
sourceOf :: [Text] -> Text
sourceOf steps = T.unlines ("foldseq 1" : "sheet square" : steps)

-- | Every move of a sequence, those inside blocks included, in the order they
-- are written.
allMoves :: Sequence -> [Move]
allMoves s = concatMap within [locValue m | located <- seqSteps s, m <- stepMoves (locValue located)]
  where
    within m =
      m : case m of
        Together members -> concatMap (within . locValue) members
        ExpectRefused _ inner -> within inner
        _ -> []
