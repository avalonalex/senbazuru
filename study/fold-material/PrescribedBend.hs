-- | Evaluate a known shape before asking the optimizer to choose one. The
-- material coordinates (positions on the unfolded sheet; see docs/glossary.md)
-- select the same cylindrical surface on every mesh. Straight triangle edges
-- are chords of that surface, so they are shorter than its material arcs.
-- 'FixedEdges' instead rotates full-length segments through the same angles:
-- it approximates the cylinder, but does NOT put matching material points at
-- identical positions. Keeping both probes separates these two effects.
--
-- 'FixedCorners' retains the existing four straight strips exactly. Refining
-- a fixed angular corner inside an uncreased panel concentrates the bend into
-- a narrower region; it is deliberately not a smooth-curvature reference.
-- Both sides coincide and share their original crease ids. These are static
-- energy probes, not equilibria, old-grip-compatible endpoints or fold paths.
-- No correction, optimization or new material rule is used here.
module PrescribedBend
  ( BendProbe (..),
    probeMeshes,
    curvature,
    cylinderPoint,
    prescribedFixture,
    EdgeMeasure (..),
    HingeMeasure (..),
    ProbeMeasure (..),
    measureProbe,
  )
where

import ClosedCrease
import Control.Monad (forM)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import FoldBending
import FoldMaterial (meshEdges)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import UnequalCrease

data BendProbe = FlatPanels | FixedCorners | SampledCylinder | FixedEdges
  deriving stock (Eq, Show, Enum, Bounded)

probeMeshes :: [(Int, Int)]
probeMeshes = [(n, w) | n <- [1, 2, 4, 8], w <- [1, 2]]

-- | Radians per sheet length: the half-sheet turns through 0.6 radians.
curvature :: Double
curvature = 1.2

cylinderPoint :: Double -> Double -> V3
cylinderPoint distance y = V3 (sin (curvature * distance) / curvature) y (2 * sin (curvature * distance / 2) ^ (2 :: Int) / curvature)

-- | Reuse material topology and the original passive and upper-band springs.
-- Positions replace the old guess directly. Old boundary holds are NOT
-- applied; the gallery measures their displacement instead of claiming an
-- accepted endpoint. ClosedCrease's profiles are updated for export metadata.
prescribedFixture :: Int -> Int -> BendProbe -> Either InequalityError ClosedCrease
prescribedFixture n w probe = do
  original <- unequalCreaseWithWidth n w UpperBand
  let reference = coupledReference original
      originalMesh = closedMesh reference
      halfTurn = curvature / fromIntegral (16 * n)
      chordScale = halfTurn / sin halfTurn
      place p = case probe of
        FlatPanels -> V3 (abs (materialU p)) (materialV p) 0
        FixedCorners -> position p
        SampledCylinder -> cylinderPoint (abs (materialU p)) (materialV p)
        FixedEdges -> let V3 x y z = cylinderPoint (abs (materialU p)) (materialV p) in V3 (chordScale * x) y (chordScale * z)
      mesh = originalMesh {samples = [p {position = place p} | p <- samples originalMesh]}
      profile = [(toRational x, toRational z) | p <- samples mesh, materialU p >= 0, materialV p == -0.5, let V3 x _ z = position p]
  pure reference {closedMesh = mesh, lowerProfile = profile, upperProfile = profile}

data EdgeMeasure = EdgeMeasure
  { edgeIds :: !(Int, Int),
    edgeRest :: !Double,
    edgeActual :: !Double
  }
  deriving stock (Eq, Show)

data HingeMeasure = HingeMeasure
  { measuredHinge :: !Hinge,
    measuredAngle :: !Double,
    measuredEnergy :: !Double,
    measuredUpper :: !Bool
  }
  deriving stock (Eq, Show)

data ProbeMeasure = ProbeMeasure
  { probeEdges :: ![EdgeMeasure],
    probeHinges :: ![HingeMeasure],
    probeLowerEnergy :: !Double,
    probeUpperEnergy :: !Double,
    probeControlEnergy :: !Double,
    probeCreaseEnergy :: !Double,
    probeLengthSquares :: !Double,
    probeRelativeError :: !Double,
    probeCreaseError :: !Double
  }
  deriving stock (Eq, Show)

-- | Length rows use absolute length errors, not strains or area weights.
-- Half the length weight times their squared sum shares bendingEnergy's
-- convention. The line search in CoupledCrease reports twice this total;
-- make that factor explicit in the gallery rather than mixing conventions.
measureProbe :: ClosedCrease -> Either InequalityError ProbeMeasure
measureProbe fixture = do
  edges <- forM (meshEdges mesh) $ \(a, b) -> do
    p <- vertex a
    q <- vertex b
    let rest = sqrt ((materialU p - materialU q) ^ (2 :: Int) + (materialV p - materialV q) ^ (2 :: Int))
    pure (EdgeMeasure (a, b) rest (norm (position p ^-^ position q)))
  hinges <- forM (closedHinges fixture) $ \h -> do
    (actual, _) <- first (InequalityError . explain) (hingeAngle h vertices)
    let (a, b, _, _) = hingeVertices h
    p <- vertex a
    q <- vertex b
    pure (HingeMeasure h actual (hingeStiffness h * angleError actual (hingeRest h) ^ (2 :: Int) / 2) (materialU p + materialU q < 0))
  let passive upper = sum [measuredEnergy h | h <- hinges, hingeRole (measuredHinge h) == PanelBend, measuredUpper h == upper]
      control = sum [measuredEnergy h | h <- hinges, hingeRole (measuredHinge h) == BendControl]
      crease = [h | h <- hinges, SurfaceCrease _ <- [hingeRole (measuredHinge h)]]
  pure (ProbeMeasure edges hinges (passive False) (passive True) control (sum (map measuredEnergy crease)) (sum [(edgeActual e - edgeRest e) ^ (2 :: Int) | e <- edges]) (maximum (0 : [abs (edgeActual e / edgeRest e - 1) | e <- edges])) (maximum (0 : [abs (angleError (measuredAngle h) pi) | h <- crease])))
  where
    mesh = closedMesh fixture
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    vertex i = maybe (Left (InequalityError ("prescribed probe lost material vertex " <> tshow i))) Right (IM.lookup i vertices)
