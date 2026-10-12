-- | The blintz's gallery: @blintz.foldseq@, run and drawn by
-- "SequenceGallery". The blintz base, one of the standard shapes many models
-- start from (see docs/glossary.md, \"Origami\"), folds a square's four
-- corners to its centre; the sequence then reopens the first corner. Its folds
-- are mountain folds, which take the corners below the sheet's xy plane, so
-- the camera looks up from below to see the flaps.
--
-- The study's hand-written recipe drew the same page from its own turns until
-- the run was shown equal to it (#493); @test/golden/checked-blintz.svg@ is
-- the guard that comparison was.
module BlintzGallery (blintzGallery) where

import Senbazuru.Geometry.V3 (V3 (..))
import SequenceGallery (Gallery (..), PartWay (..))

-- | Eleven figures: the open square, then each of the five turns halfway and
-- at its end. The turns fold the four corners behind and reopen the first.
blintzGallery :: Gallery
blintzGallery =
  Gallery
    { galleryName = "blintz",
      gallerySource = "blintz.foldseq",
      galleryDirectory = "checked-blintz",
      galleryTitle = "Blintz base, then reopen one corner",
      galleryViewDirection = V3 (-1) 0 1,
      galleryPageWidth = 1120,
      galleryPageHeight = 900,
      galleryPartWay = replicate 5 (PartWay "halfway" 0.5),
      galleryTemplate = "study/fold-material/blintz.html"
    }
