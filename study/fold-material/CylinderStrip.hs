-- | The control for the false-crease measure: a strip of paper bent into a
-- cylinder, which is a curve and not a fold (PRD 11, A-11-2). It is a module
-- of its own, not part of "PaperScreen", because it is a shape and not a
-- measure: the measures read any mesh, and this is one mesh they are
-- checked on.
--
-- The strip is the one research note Y3 used, as experiment P: one sheet
-- side long and a quarter wide, cut into square cells of side @1/n@, each
-- split by one diagonal, and laid on a cylinder whose straight lines, its
-- /generators/, run at 45 degrees across it. Every vertex sits exactly on the
-- cylinder. Nothing is solved.
--
-- A mesh can only sample a curve. Each join bends by the angle between the
-- two triangles either side, and splitting every cell in four halves that
-- angle, so a curve's joins all fall below a threshold once the mesh is fine
-- enough. A fold's stay sharp at any resolution. That is the argument for a
-- false-crease measure that sums only the joins past a threshold, and this
-- strip is its test.
--
-- What a newcomer would get wrong is the sum over every join, with no
-- threshold. It does not vanish, which is why the measure needs its
-- threshold, but it is not a property of the curve either: it depends on how
-- the cells are cut. Cut along the bend, every diagonal lies on a generator,
-- and the two triangles either side of any other edge lie in one plane, so
-- the diagonals carry the whole bend and sum to the strip's area over the
-- cylinder's radius at every resolution. Cut across it, the diagonals bend
-- against the curve and the cell sides with it, and the sum of their sizes
-- grows as the cells shrink. docs/notes/fold-or-curve.md has both.
--
-- The strip is placed, not relaxed. Y3 held both end columns of cells on the
-- cylinder and relaxed the rest, and its solver's ridges across the bend
-- ("locking") made the coarse joins sharper still. The study's solver cannot
-- do that here: it stops only when every edge is within 10^-5 of its flat
-- length, and an edge between two held vertices is a chord of the cylinder,
-- shorter than the paper it spans by more than that, which nothing moves.
module CylinderStrip (Diagonal (..), placedStrip, stripJoins) where

import FoldBending (Bending (..), BendingError, buildPanelHinges, hingeBends, joinsWhere)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))

-- | Which way each cell's diagonal runs, against generators at -45 degrees:
-- across them, from a cell's lower left corner to its upper right, or along
-- them, from lower right to upper left.
data Diagonal = AcrossBend | AlongBend
  deriving stock (Eq, Show)

-- | Cells across the strip at @n@ along: a quarter as many, so the strip is
-- a quarter as wide as it is long when @n@ is a multiple of four.
cellsAcross :: Int -> Int
cellsAcross n = n `div` 4

-- | The flat strip, @n@ cells along its length and 'cellsAcross' across,
-- every vertex at its place on the sheet.
stripMesh :: Int -> Diagonal -> MaterialMesh
stripMesh n diagonal = Mesh points cells
  where
    across = cellsAcross n
    at i j = j * (n + 1) + i
    points = [Sample (V2 u v) (V3 u v 0) | j <- [0 .. across], i <- [0 .. n], let u = fromIntegral i / fromIntegral n, let v = fromIntegral j / fromIntegral n]
    cells = concat [split (at i j) (at (i + 1) j) (at (i + 1) (j + 1)) (at i (j + 1)) | j <- [0 .. across - 1], i <- [0 .. n - 1]]
    split a b c d = case diagonal of
      AcrossBend -> [(a, b, c), (a, c, d)]
      AlongBend -> [(a, b, d), (b, c, d)]

-- | The strip at @n@ cells along, laid on the cylinder that turns it through
-- @turn@ radians across its width, generators at -45 degrees. Nothing for
-- fewer than four cells along, which leaves none across, or for a turn that
-- is not a positive number.
--
-- Distance along a generator stays straight, and distance across the
-- generators wraps round the circle. The radius makes the strip's whole
-- extent across the generators exactly @turn@ radians of arc, measured from
-- the strip's middle, so every vertex keeps its distance from the middle
-- along the paper.
placedStrip :: Int -> Diagonal -> Double -> Maybe MaterialMesh
placedStrip n diagonal turn
  | n < 4 || isNaN turn || isInfinite turn || turn <= 0 = Nothing
  | otherwise = Just flat {samples = [p {position = onCylinder (sampleMaterial p)} | p <- samples flat]}
  where
    flat = stripMesh n diagonal
    width = fromIntegral (cellsAcross n) / fromIntegral n
    middle = V2 0.5 (width / 2)
    angle = -(pi / 4)
    generator = V2 (cos angle) (sin angle)
    across = V2 (negate (sin angle)) (cos angle)
    extents = [dot (c ^-^ middle) across | c <- [V2 0 0, V2 1 0, V2 1 width, V2 0 width]]
    radius = (maximum extents - minimum extents) / turn
    onCylinder p =
      let s = dot (p ^-^ middle) across
          t = dot (p ^-^ middle) generator
       in t *^ lift generator ^+^ (radius * sin (s / radius)) *^ lift across ^+^ (radius * (1 - cos (s / radius))) *^ V3 0 0 1
    lift (V2 x y) = V3 x y 0

-- | Every join of a strip, as its length on the flat sheet and its signed
-- bend in degrees. The strip has no creases, so every interior edge is a
-- join.
stripJoins :: MaterialMesh -> Either BendingError [(Double, Double)]
stripJoins mesh = do
  hinges <- buildPanelHinges (Bending 1 0.2) mesh
  bends <- hingeBends hinges mesh
  pure (joinsWhere (const True) mesh bends)
