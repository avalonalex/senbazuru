-- | Compare triangle approximations with a fixed continuous bend whose cost
-- is known analytically. Material coordinates locate the unfolded sheet;
-- see docs/glossary.md. Refining a mesh must not refit the reference curve:
-- otherwise changing shape and approximation error become indistinguishable.
-- HeldBend supplies each common curve once; this module only discretizes it.
--
-- Samples stay on that curve but shorten straight triangle edges. Restoring
-- each chord's material length keeps its direction and moves the outer grip.
-- Both are diagnostic controls. Neither copies grips back, minimizes energy,
-- or describes a continuous folding motion. The two panels coincide but share
-- only their original crease vertices; subdivision edges are passive bends.
module BendRefinement
  ( ReferenceMesh (..),
    referenceMeshes,
    referenceColumns,
    ReferenceGrid,
    makeReferenceGrid,
    gridColumns,
    referenceGrid,
    gridProfile,
    gridReference,
    gridAngularCost,
    ReferenceConstruction (..),
    referenceProfile,
    fixedReference,
    referenceAngularCost,
  )
where

import ClosedCrease
import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.Text (Text)
import FoldBending
import HeldBend
import OuterStrip (OuterMesh (RestOnly), outerColumns)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

-- | A bounded ladder, not a new resolution setting for the material solver.
-- The uneven anchor reproduces the prior rest-only comparison and is not
-- inserted into the uniform ladder's successive-mesh calculations.
data ReferenceMesh = Uniform64 | Uniform128 | Uniform256 | Uniform512 | Uniform1024 | Uneven120
  deriving stock (Eq, Show, Enum, Bounded)

referenceMeshes :: [(ReferenceMesh, String, Text)]
referenceMeshes = [(Uniform64, "64", "64 triangles"), (Uniform128, "128", "128 triangles"), (Uniform256, "256", "256 triangles"), (Uniform512, "512", "512 triangles"), (Uniform1024, "1024", "1,024 triangles"), (Uneven120, "120", "120 triangles · uneven anchor")]

referenceColumns :: ReferenceMesh -> [Rational]
referenceColumns Uneven120 = outerColumns RestOnly
referenceColumns Uniform64 = uniformColumns 8
referenceColumns Uniform128 = uniformColumns 16
referenceColumns Uniform256 = uniformColumns 32
referenceColumns Uniform512 = uniformColumns 64
referenceColumns Uniform1024 = uniformColumns 128

uniformColumns :: Int -> [Rational]
uniformColumns count = [fromIntegral i / fromIntegral (2 * count) | i <- [0 .. count]]

-- | A validated material grid lets the same construction measure a new
-- placement policy without copying the paper or spring implementation. Keep
-- the original sheet ends and inner-grip boundary, and reject columns whose
-- conversion to floating-point positions would collapse or overflow.
newtype ReferenceGrid = ReferenceGrid {gridColumns :: [Rational]}
  deriving stock (Eq, Show)

makeReferenceGrid :: [Rational] -> Either ClosedCreaseError ReferenceGrid
makeReferenceGrid columns = do
  let coordinates = map (fromRational :: Rational -> Double) columns
  unless (take 1 columns == [0] && take 1 (reverse columns) == [1 / 2] && 1 / 8 `elem` columns && and (zipWith (<) coordinates (drop 1 coordinates)) && all (\x -> not (isNaN x || isInfinite x)) coordinates) $
    Left (ClosedCreaseError "reference grid needs increasing finite material columns from 0 to 1/2, including the inner-grip boundary 1/8")
  pure (ReferenceGrid columns)

referenceGrid :: ReferenceMesh -> ReferenceGrid
referenceGrid = ReferenceGrid . referenceColumns

data ReferenceConstruction = SampledReference | LengthReference
  deriving stock (Eq, Show, Enum, Bounded)

-- | Restore lengths by integrating chord directions, not by scaling all
-- coordinates. The flat inner strip stays exactly fixed. No normalization
-- changes the energy weights, which come from the original material mesh.
referenceProfile :: ReferenceMesh -> ReferenceConstruction -> HeldCurve -> [V3]
referenceProfile = gridProfile . referenceGrid

gridProfile :: ReferenceGrid -> ReferenceConstruction -> HeldCurve -> [V3]
gridProfile grid construction curve = case construction of
  SampledReference -> points
  LengthReference -> scanl (^+^) (V3 0 0 0) [((b - a) / norm chord) *^ chord | (a, b, chord) <- chords]
  where
    columns = map fromRational (gridColumns grid)
    points = [curvePoint curve s 0 | s <- columns]
    chords = [(a, b, q ^-^ p) | ((a, p), (b, q)) <- zip (zip columns points) (drop 1 (zip columns points))]

fixedReference :: ReferenceMesh -> ReferenceConstruction -> HeldCurve -> Either ClosedCreaseError ClosedCrease
fixedReference = gridReference . referenceGrid

gridReference :: ReferenceGrid -> ReferenceConstruction -> HeldCurve -> Either ClosedCreaseError ClosedCrease
gridReference grid construction curve = do
  let columns = map fromRational (gridColumns grid)
      profile = gridProfile grid construction curve
      half sign = [materialSample (sign * u) y (V3 x y z) | (u, V3 x _ z) <- zip columns profile, y <- [-0.5, 0, 0.5]]
      lower = half 1
      upperId i = if i < 3 then i else length lower + i - 3
      cell i j = let a = 3 * i + j; b = 3 * (i + 1) + j in [(a, b, b + 1), (a, b + 1, a + 1)]
      faces = concat [cell i j | i <- [0 .. length columns - 2], j <- [0, 1]]
      mesh = Mesh (lower ++ drop 3 (half (-1))) (faces ++ [(upperId a, upperId c, upperId b) | (a, b, c) <- faces])
      root h = let (a, b, _, _) = hingeVertices h in if a < 3 && b < 3 then h {hingeRole = SurfaceCrease (EdgeId 0), hingeRest = pi, hingeStiffness = 0.5} else h
      rationalProfile = [(toRational x, toRational z) | V3 x _ z <- profile]
  hinges <- first (ClosedCreaseError . explain) (buildPanelHinges (Bending 1 0.2) mesh)
  pure (ClosedCrease mesh (replicate (length faces) (FaceId 0) ++ replicate (length faces) (FaceId 1)) (map root hinges) [0, 1, 2] rationalProfile rationalProfile)

-- | Scalar comparison with the measured 3D hinge costs, per unit-width panel.
-- Neighboring chord directions turn through delta; the original material
-- spacing h gives 0.5 * 0.2 * delta^2 / h. Full-length and sampled controls
-- have the same directions and therefore the same angular cost, despite
-- their different length error and grip displacement.
referenceAngularCost :: ReferenceMesh -> HeldCurve -> Double
referenceAngularCost = gridAngularCost . referenceGrid

gridAngularCost :: ReferenceGrid -> HeldCurve -> Double
gridAngularCost grid curve = sum [0.1 * (q - p) ^ (2 :: Int) / ((a + b) / 2) | ((a, p), (b, q)) <- zip rows (drop 1 rows)]
  where
    columns = map fromRational (gridColumns grid)
    rows = [(b - a, atan2 z x) | (a, b) <- zip columns (drop 1 columns), let V3 x _ z = curvePoint curve b 0 ^-^ curvePoint curve a 0]
