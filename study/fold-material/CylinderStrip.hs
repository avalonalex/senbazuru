-- | The control for the false-crease measure: a strip of paper bent into a
-- cylinder, which is a curve and not a fold (PRD 11, A-11-2).
--
-- The strip is the one research note Y3 used, as experiment P: one sheet
-- side long and a quarter wide, cut into square cells of side @1/n@, each
-- split by one diagonal, and laid on a cylinder whose straight lines, its
-- /generators/, run at 45 degrees across it. Every vertex sits exactly on the
-- cylinder. Nothing is solved.
--
-- A mesh can only sample a curve: each join bends by the angle between two
-- neighbouring triangles, and splitting every cell halves that angle. So the
-- joins of a curve all fall below a threshold once the mesh is fine enough,
-- while the turning summed over every join, length times angle, stays about
-- what the curve turns. A fold is the opposite: its bend stays sharp at any
-- resolution. That is the whole argument for a false-crease measure that sums
-- only joins past a threshold, and this strip is its test.
--
-- Two things to get right. The strip is placed, not relaxed. Y3 relaxed it
-- with its own solver, whose ridges across the bend ("locking") made the
-- coarse joins sharper still; the study's solver did not settle it within
-- 400 iterations a stage. And a placed mesh is only nearly paper: a straight
-- edge between two points on the cylinder is a chord, a little shorter than
-- the arc of paper it spans, unless it runs along a generator. Cut along the
-- bend, every diagonal does. Cut across it, every diagonal crosses the
-- generators square on and shortens most, which is why that strip's
-- unthresholded turning drifts with resolution while the other's does not.
module CylinderStrip (Diagonal (..), stripMesh, onCylinder, placedStrip, stripJoins) where

import Data.IntMap.Strict qualified as IM
import FoldBending (Bending (..), BendingError (..), Hinge (..), buildPanelHinges, hingeAngle)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))

-- | Which way each cell's diagonal runs, against generators at -45 degrees:
-- across them, from a cell's lower left corner to its upper right, or along
-- them, from lower right to upper left.
data Diagonal = AcrossBend | AlongBend
  deriving stock (Eq, Show)

-- | The flat strip, @n@ cells along its length and @n/4@ across, every
-- vertex at its place on the sheet.
stripMesh :: Int -> Diagonal -> MaterialMesh
stripMesh n diagonal = Mesh points cells
  where
    across = n `div` 4
    at i j = j * (n + 1) + i
    points = [Sample (V2 u v) (V3 u v 0) | j <- [0 .. across], i <- [0 .. n], let u = fromIntegral i / fromIntegral n, let v = fromIntegral j / fromIntegral n]
    cells = concat [split (at i j) (at (i + 1) j) (at (i + 1) (j + 1)) (at i (j + 1)) | j <- [0 .. across - 1], i <- [0 .. n - 1]]
    split a b c d = case diagonal of
      AcrossBend -> [(a, b, c), (a, c, d)]
      AlongBend -> [(a, b, d), (b, c, d)]

-- | Where a point of the strip lies on the cylinder turning through @turn@
-- radians, generators at @generator@ radians: distance along a generator
-- stays straight, and distance across the generators wraps round the
-- circle. The radius makes the strip's whole width across the generators
-- exactly @turn@ radians of arc, so a point's distance from the middle,
-- measured along the paper, is what it was on the sheet.
onCylinder :: Double -> Double -> V2 -> V3
onCylinder generator turn p = t *^ lift g ^+^ (radius * sin (s / radius)) *^ lift across ^+^ (radius * (1 - cos (s / radius))) *^ V3 0 0 1
  where
    g = V2 (cos generator) (sin generator)
    across = V2 (negate (sin generator)) (cos generator)
    middle = V2 0.5 0.125
    s = dot (p ^-^ middle) across
    t = dot (p ^-^ middle) g
    widths = [dot (c ^-^ middle) across | c <- [V2 0 0, V2 1 0, V2 1 0.25, V2 0 0.25]]
    radius = (maximum widths - minimum widths) / turn
    lift (V2 x y) = V3 x y 0

-- | The strip at @n@ cells along, laid on the cylinder turning through
-- @turn@ radians, generators at -45 degrees.
placedStrip :: Int -> Diagonal -> Double -> MaterialMesh
placedStrip n diagonal turn = flat {samples = [p {position = onCylinder (-(pi / 4)) turn (sampleMaterial p)} | p <- samples flat]}
  where
    flat = stripMesh n diagonal

-- | Every join of a strip, as its length on the flat sheet and its bend in
-- degrees. The strip has no creases, so every interior edge is a join.
stripJoins :: MaterialMesh -> Either BendingError [(Double, Double)]
stripJoins mesh = do
  hinges <- buildPanelHinges (Bending 1 0.2) mesh
  mapM join hinges
  where
    points = IM.fromList (zip [0 ..] (samples mesh))
    join h = do
      (angle, _) <- hingeAngle h points
      let (a, b, _, _) = hingeVertices h
      u <- material a
      v <- material b
      pure (norm (u ^-^ v), abs angle * 180 / pi)
    material i = maybe (Left (MissingHingeVertex i)) (Right . sampleMaterial) (IM.lookup i points)
