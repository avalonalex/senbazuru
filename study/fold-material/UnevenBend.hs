-- | Known bends on the four outer-strip meshes, without choosing a new
-- equilibrium. Material coordinates locate the unfolded sheet; see
-- docs/glossary.md. Both material halves occupy the same surface, retaining
-- their distinct vertices and shared crease. Old outer grips are not applied.
--
-- Exact samples keep matching material points on the same smooth reference,
-- but their straight edges are chords and therefore too short. FullSegments
-- instead adds one full-length vector per material strip, in its chord's
-- direction. A single global scale would be wrong on uneven strips: each
-- chord has a different shortening. Neither construction calls a solver.
--
-- The support formulas independently integrate the prescribed curvature over
-- intervals halfway to neighboring columns. Missing boundary intervals and
-- averaging across the flat-to-curved transition are separate energy deficits.
-- This is a reference for the current discrete rule, not calibrated paper.
module UnevenBend
  ( ReferenceBend (..),
    BendConstruction (..),
    bendStart,
    referencePoint,
    unevenFixture,
    BendSupport (..),
    bendSupports,
    referenceEnergy,
    predictedLengthSquares,
  )
where

import BandBoundary (BoundaryRule (..))
import ClosedCrease
import Control.Monad (forM)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Map.Strict qualified as M
import OuterStrip
import PrescribedBend (curvature, cylinderPoint)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import UnequalCrease (UnequalControl (..))

data ReferenceBend = CylinderBend | AfterHeldStrip
  deriving stock (Eq, Show, Enum, Bounded)

data BendConstruction = SurfaceSamples | FullSegments
  deriving stock (Eq, Show, Enum, Bounded)

bendStart :: ReferenceBend -> Double
bendStart CylinderBend = 0
bendStart AfterHeldStrip = 1 / 8

-- | Tangent direction is continuous at the start: no finite corner or new
-- crease is introduced. Curvature changes there from zero to 1.2.
referencePoint :: ReferenceBend -> Double -> Double -> V3
referencePoint ref s y
  | s <= start = V3 s y 0
  | otherwise = let V3 x _ z = cylinderPoint (s - start) y in V3 (start + x) y z
  where
    start = bendStart ref

unevenFixture :: OuterMesh -> ReferenceBend -> BendConstruction -> Either InequalityError ClosedCrease
unevenFixture choice ref construction = do
  original <- outerFixture choice OriginalTurns MatchedHolds
  let base = coupledReference original
      mesh = closedMesh base
      columns = map fromRational (outerColumns choice)
      directions = [let h = b - a; angle = curvature * max 0 ((a + b) / 2 - bendStart ref) in V3 (h * cos angle) 0 (h * sin angle) | (a, b) <- zip columns (drop 1 columns)]
      full = M.fromList (zip columns (scanl (^+^) (V3 0 0 0) directions))
      place p = case construction of
        SurfaceSamples -> pure (referencePoint ref (abs (materialU p)) (materialV p))
        FullSegments -> case M.lookup (abs (materialU p)) full of
          Just (V3 x _ z) -> pure (V3 x (materialV p) z)
          Nothing -> Left (InequalityError "prescribed uneven bend lost a material column")
  points <- forM (samples mesh) $ \p -> do q <- place p; pure p {position = q}
  let profile = [(toRational x, toRational z) | p <- points, materialU p >= 0, materialV p == -0.5, let V3 x _ z = position p]
  pure base {closedMesh = mesh {samples = points}, lowerProfile = profile, upperProfile = profile}

data BendSupport = BendSupport
  { supportDistance :: !Double,
    supportInterval :: !(Double, Double),
    supportActiveLength :: !Double,
    supportTurn :: !Double,
    supportEnergy :: !Double,
    supportIntegral :: !Double
  }
  deriving stock (Eq, Show)

-- | Costs are for a whole unit-width panel. The two width segments divide
-- that cost between them. If only part of an interval bends, the discrete
-- spring squares its average curvature, rather than averaging its square.
bendSupports :: OuterMesh -> ReferenceBend -> [BendSupport]
bendSupports choice ref =
  [ let left = (a + b) / 2
        right = (b + c) / 2
        width = right - left
        active = max 0 (right - max left (bendStart ref))
        turn = curvature * active
     in BendSupport b (left, right) active turn (0.1 * turn * turn / width) (0.1 * curvature * curvature * active)
    | (a, b, c) <- zip3 columns (drop 1 columns) (drop 2 columns)
  ]
  where
    columns = map fromRational (outerColumns choice)

referenceEnergy :: ReferenceBend -> Double
referenceEnergy ref = 0.1 * curvature * curvature * (0.5 - bendStart ref)

-- | Count all horizontal and diagonal edges on both panels, independently
-- of the 3D mesh traversal. Width edges have zero residual. Every bend start
-- is a column, so no segment crosses the flat-to-curved transition.
predictedLengthSquares :: OuterMesh -> ReferenceBend -> BendConstruction -> Double
predictedLengthSquares _ _ FullSegments = 0
predictedLengthSquares choice ref SurfaceSamples =
  sum
    [ let h = b - a
          chord = if b <= bendStart ref then h else 2 * sin (curvature * h / 2) / curvature
          diagonal = sqrt (chord * chord + 0.25) - sqrt (h * h + 0.25)
       in 6 * (chord - h) ^ (2 :: Int) + 4 * diagonal * diagonal
      | (a, b) <- zip columns (drop 1 columns)
    ]
  where
    columns = map fromRational (outerColumns choice)
