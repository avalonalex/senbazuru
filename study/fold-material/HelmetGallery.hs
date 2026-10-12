-- | The helmet base's gallery: @helmet.foldseq@, run and drawn by
-- "SequenceGallery". A /base/ is a standard shape many models start from (see
-- docs/glossary.md, \"Origami\"); the helmet base is a square folded
-- diagonally in half, with both corners of the doubled triangle then brought
-- to its tip. The camera looks at the moving flaps from above.
--
-- The study's hand-written recipe drew this page until #534 deleted it; #529
-- had shown the run draws it byte for byte, and
-- @test/golden/checked-helmet.svg@ is the guard that comparison was.
module HelmetGallery (helmetGallery) where

import Senbazuru.Explain (tshow)
import Senbazuru.Geometry.V3 (V3 (..))
import SequenceGallery (Gallery (..), PartWay (..))

-- | Seven figures: the open square, then an intermediate and a flat pose of
-- each turn. At this camera's 45-degree elevation the first turn at 90
-- degrees has the open sheet's silhouette, so it is shown at 120 degrees
-- instead; the corner turns at 90. Every turn is a half turn, so a pose d
-- degrees along one is d/180 of the way.
helmetGallery :: Gallery
helmetGallery =
  Gallery
    { galleryName = "helmet",
      gallerySource = "helmet.foldseq",
      galleryDirectory = "checked-helmet",
      galleryTitle = "Three turns to the helmet base",
      galleryViewDirection = V3 (-1) 1 (negate (sqrt 2)),
      galleryPageWidth = 1120,
      galleryPageHeight = 620,
      galleryPartWay = [degrees 120, degrees 90, degrees 90],
      galleryTemplate = "study/fold-material/helmet.html"
    }
  where
    degrees :: Int -> PartWay
    degrees d = PartWay (tshow d <> "°") (fromIntegral d / 180)
