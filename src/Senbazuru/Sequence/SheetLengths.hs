-- |
-- Module      : Senbazuru.Sequence.SheetLengths
-- Description : Sheet lengths, the units a fold sequence names paper in, and the one place they are converted.
--
-- An author names paper in /sheet lengths/ (see docs/glossary.md, "Fold
-- sequences"): the sheet's bounding box, as it lies flat before any folding,
-- has its south-west corner at (0, 0) and its longer side 1. So @(1/2, 1/2)@
-- is the middle of a unit square and of a square drawn 200 millimetres wide
-- alike, and a source means the same paper on either.
--
-- __One scale on both axes, not one per side.__ The scale is the longer side,
-- so on a sheet wider than it is tall, @(1, 1)@ is off the paper, above its
-- top edge: the top edge is at v = height / width, less than 1. Scaling each
-- axis by its own side would put @(1, 1)@ on the corner, and would also turn
-- every angle on a non-square sheet, so a crease at 45° in the file would not
-- be at 45° in the author's numbers (PRDs\/02-language-semantics.md, §3).
--
-- __Why one place.__ Everything a run says to an author is in these units:
-- a refusal's point, a near miss's distance, a fold line in the report, a new
-- crease's ends. Each has to measure against the same box in the same way, or
-- two parts of one report disagree about one point. The run report once kept
-- a copy of this arithmetic, dividing where the resolver multiplied by a
-- reciprocal, which can differ in the last bit; it could not import the
-- resolver, which imports it. This module sits below both and knows no paper:
-- it takes the sheet's box, which its caller measured on the sheet laid flat.
--
-- Physical lengths, millimetres of real paper, arrive with the material study
-- (milestone M6), and are to be converted in one place of their own.
module Senbazuru.Sequence.SheetLengths
  ( sheetLengthOf,
    inSheetLengths,
    fromSheetLengths,
  )
where

import Senbazuru.Geometry (Box (..), V2 (..), boxSize)
import Senbazuru.Geometry.VectorSpace

-- | One sheet length, in the sheet's own units: the longer side of its box.
-- A sheet has extent, so it is never zero.
sheetLengthOf :: Box -> Double
sheetLengthOf box = let V2 w h = boxSize box in max w h

-- | A point of the sheet, in the sheet's own coordinates, in sheet lengths.
inSheetLengths :: Box -> V2 -> V2
inSheetLengths box p = (1 / sheetLengthOf box) *^ (p ^-^ boxMin box)

-- | A point in sheet lengths, in the sheet's own coordinates: the inverse of
-- 'inSheetLengths'.
fromSheetLengths :: Box -> V2 -> V2
fromSheetLengths box uv = boxMin box ^+^ (sheetLengthOf box *^ uv)
