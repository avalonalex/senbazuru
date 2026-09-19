-- |
-- Module      : Test.SequenceExamples
-- Description : The fold sequences that more than one spec needs, written once.
--
-- The same example has to mean the same thing in every test that uses it. The
-- blintz below is compared with its own constructors in the builder's spec and
-- printed in the printer's; it will be compared with the parse of its text,
-- and later run and compared with the study's hand-written recipe. Three
-- copies would be three chances for those tests to be about three slightly
-- different sequences.
--
-- Two sequences live here, both taken from the language's design so that a
-- test's output can be laid beside it: the 'blintz', from
-- @PRDs\/03-prd-embedded-dsl.md@, and the 'quarterFold', from
-- @PRDs\/04-prd-sequence-source-and-cli.md@.
module Test.SequenceExamples
  ( blintz,
    blintzCaptions,
    quarterFold,
  )
where

import Control.Monad (forM_)
import Data.Text (Text)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Syntax (Compass (..), Corner (..), Header (..), Line (..), Sequence)

-- | A /blintz/ folds the four corners of a square to its centre. This one then
-- reopens the first corner, so that the sequence has a move that refers back
-- to an earlier step by name.
--
-- Written exactly as the design for the language gives it
-- (@PRDs\/03-prd-embedded-dsl.md@), loop included, because the point of the
-- example is that the loop leaves no trace: the value holds three ordinary
-- steps where the @forM_@ was.
--
-- The caption says \"behind\" and the move says 'mountain'. They are the same
-- fold: \"behind\" is how a book says it, and the tree stores only the sense.
--
-- The sheet's path is relative to the repository root, not to @examples\/@.
-- The text of this sequence will be saved at the root, as @blintz.foldseq@,
-- when the parser arrives; a sheet's path is read relative to the file that
-- names it, and the two have to name their sheet with the same words to be
-- equal.
blintz :: Sequence
blintz = sequenceOf (header "Blintz base, then reopen one corner" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
  c1 <- step "c1" "Fold the south-east corner behind, to the centre." $ fold mountain (cornerOf SouthEast `onto` centre)
  forM_ [(NorthEast, "north-east"), (NorthWest, "north-west"), (SouthWest, "south-west")] $ \(c, word) ->
    step_ ("Fold the " <> word <> " corner behind, to the centre.") $ fold mountain (cornerOf c `onto` centre)
  step_ "Reopen the first corner." $ unfold [c1]

-- | The blintz's five captions, in order, as the text of the sequence spells
-- them.
blintzCaptions :: [Text]
blintzCaptions =
  [ "Fold the south-east corner behind, to the centre.",
    "Fold the north-east corner behind, to the centre.",
    "Fold the north-west corner behind, to the centre.",
    "Fold the south-west corner behind, to the centre.",
    "Reopen the first corner."
  ]

-- | The quarter fold: a square folded in half, then in half again. It is the
-- sequence the language's design reads line by line
-- (@PRDs\/04-prd-sequence-source-and-cli.md@), and the fixture it names,
-- @examples\/quarter-fold-steps.fold@, is the one a run will be compared with.
--
-- Each fold is named by the two sides of the sheet it brings together. There
-- is no builder for that form, a line laid onto a line, so it is written with
-- the tree's own constructor, 'LineOnto'. The 'Nothing' is its optional
-- @nearest@ point, which two parallel sides do not need: only one fold lays
-- the west side onto the east.
--
-- The anchor, @(3\/4, 1\/4)@, is in the south-east quarter, the one piece of
-- paper neither step moves.
quarterFold :: Sequence
quarterFold = sequenceOf top $ do
  _ <- step "half" "Fold the left half behind, onto the right." $ fold behind (LineOnto (edge West) (edge East) Nothing)
  _ <- step "quarter" "Fold the top half down in front, onto the bottom." $ fold inFront (LineOnto (edge North) (edge South) Nothing)
  pure ()
  where
    top =
      (header "A square folded into quarters" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4))))
        { hClosing = Just "Folded into quarters."
        }
