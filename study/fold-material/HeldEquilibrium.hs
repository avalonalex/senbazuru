-- | Let the two touching panels settle between the original grips, starting
-- from one common smooth curve. Material coordinates identify the unfolded
-- sheet (see docs/glossary.md); current positions are only an initial guess.
-- Refining that guess never changes the material's flat rest shape or adds
-- springs that prefer the curve. Both panels may move in all three directions.
--
-- This bounded experiment separates placement from triangle count. Whole-bend
-- priority is fixed from the reference curve before solving, not adapted to
-- the answer. Inner-strip holds constrain the same material region on every
-- grid. The outer edge uses the authored grip, allowing only a reported
-- roundoff correction of the common curve's endpoint, never a new fitted grip.
module HeldEquilibrium
  ( HeldLayout (..),
    HeldBudget (..),
    HeldCase (..),
    heldCases,
    heldCase,
    equilibriumSettings,
    equilibriumWeights,
  )
where

import BendRefinement
import ClosedCrease
import Control.Monad (unless)
import CoupledCrease
import CreaseInequality
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import FoldRelaxation
import HeldBend
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import TransitionRefinement

data HeldLayout = UniformLayout | WholeBendLayout deriving stock (Eq, Show)

data HeldBudget = Triangles128 | Triangles256 | Triangles512 deriving stock (Eq, Show)

data HeldCase = HeldCase
  { heldGrid :: !ReferenceGrid,
    caseCurve :: !HeldCurve,
    heldFixture :: !CoupledFixture,
    heldGripRoundoff :: !Double
  }
  deriving stock (Show)

heldCases :: [(String, HeldLayout, HeldBudget)]
heldCases = [("uniform-128", UniformLayout, Triangles128), ("whole-128", WholeBendLayout, Triangles128), ("uniform-256", UniformLayout, Triangles256), ("whole-256", WholeBendLayout, Triangles256)]

equilibriumSettings :: Settings
equilibriumSettings = Settings 40 1e-5

equilibriumWeights :: [Double]
equilibriumWeights = [1e2, 1e4, 1e6, 1e8, 1e9, 1e10]

heldCase :: HeldLayout -> HeldBudget -> Either InequalityError HeldCase
heldCase layout budget = do
  curve <- commonCurveWith SmoothTransition
  grid <- first (InequalityError . explain) $ case layout of
    UniformLayout -> Right (referenceGrid meshSize)
    WholeBendLayout -> wholeBendGrid meshSize curve
  reference <- first (InequalityError . explain) (gridReference grid SampledReference curve)
  target@(V3 x _ z) <- gripTarget
  let roundoff = norm (curvePoint curve 0.5 0 ^-^ target)
  unless (roundoff <= 1e-12) (Left (InequalityError "common smooth curve misses the original grip beyond roundoff"))
  let snap p = if abs (materialU p) == 0.5 then p {position = V3 x (materialV p) z} else p
      seed = (closedMesh reference) {samples = map snap (samples (closedMesh reference))}
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples seed), abs (materialU p) <= heldStart || abs (materialU p) == 0.5]
      fixture = CoupledFixture reference {closedMesh = seed} seed pins
  checkCoupledMaterial fixture seed
  pure (HeldCase grid curve fixture roundoff)
  where
    meshSize = case budget of Triangles128 -> Uniform128; Triangles256 -> Uniform256; Triangles512 -> Uniform512
