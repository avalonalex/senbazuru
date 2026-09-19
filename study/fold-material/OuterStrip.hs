-- | Separate resolution outside the bending band from resolution everywhere
-- else. Material coordinates locate the unfolded paper (docs/glossary.md).
-- All four meshes sample the same piecewise-straight starting shape; selecting
-- columns changes its triangulation, never interpolates a folding motion.
-- Both panels gain or lose the column at 15/32 together, and still share only
-- the original crease. The numerical solver and material law are unchanged.
--
-- A band spring represents the interval halfway to its neighboring columns.
-- Unequal widths change that interval and its covered fraction. In particular,
-- adding the outer column changes the fractional spring at the band end even
-- though the physical band and total loading are fixed. Retain those supports
-- explicitly: this is a mesh experiment, not an identical spring-matrix test.
module OuterStrip
  ( OuterMesh (..),
    outerMeshes,
    outerColumns,
    outerInterval,
    outerFixture,
    outerBoundaryMeasures,
    outerPairs,
  )
where

import BandBoundary
import ClosedCrease
import Control.Monad (forM, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import FoldBending
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..))
import Senbazuru.Origami.Surface
import UnequalCrease

data OuterMesh = Coarse | OuterOnly | RestOnly | Fine
  deriving stock (Eq, Ord, Show, Enum, Bounded)

outerMeshes :: [(OuterMesh, String, Text)]
outerMeshes = [(Coarse, "coarse", "Coarse · 64 triangles"), (OuterOnly, "outer", "Outer strip only · 72 triangles"), (RestOnly, "rest", "Rest only · 120 triangles"), (Fine, "fine", "Fully refined · 128 triangles")]

outerColumns :: OuterMesh -> [Rational]
outerColumns choice = [fromIntegral i / 32 | i <- [0 :: Int .. 16], keep i]
  where
    keep i = case choice of
      Coarse -> even i
      OuterOnly -> even i || i == 15
      RestOnly -> i /= 15
      Fine -> True

-- | Every pair is nested, so each source material vertex has an exact match.
outerPairs :: [(OuterMesh, OuterMesh)]
outerPairs = [(Coarse, OuterOnly), (Coarse, RestOnly), (OuterOnly, Fine), (RestOnly, Fine), (Coarse, Fine)]

-- | Full support and its clipped part, calculated in exact material fractions.
-- End columns have no two-sided transverse spring; empty overlap is no load.
outerInterval :: OuterMesh -> Double -> Maybe ((Double, Double), (Double, Double))
outerInterval _ distance | isNaN distance || isInfinite distance = Nothing
outerInterval choice distance = case [ ((fromRational left, fromRational right), (fromRational lo, fromRational hi))
                                       | (a, b, c) <- zip3 columns (drop 1 columns) (drop 2 columns),
                                         b == toRational distance,
                                         let left = (a + b) / 2; right = (b + c) / 2; lo = max (1 / 8) left; hi = min (7 / 16) right,
                                         hi > lo
                                     ] of
  value : _ -> Just value
  [] -> Nothing
  where
    columns = outerColumns choice

outerFixture :: OuterMesh -> BoundaryRule -> UnequalControl -> Either InequalityError CoupledFixture
outerFixture choice rule control = do
  unless (control `elem` [MatchedHolds, UpperBand, BandWithoutContact]) (Left (InequalityError "outer-strip refinement requires matched or band controls"))
  -- The fine reference contains every required point, with the original exact
  -- rational profile construction. Rebuilding cells keeps the original winding
  -- and ids on the two uniform controls, checked against their existing fixtures.
  original <- adapt (closedCreaseWithWidth 4 1 BentTouching)
  let source = M.fromList [((materialU p, materialV p), p) | p <- samples (closedMesh original)]
      columns = outerColumns choice
      point u v = maybe (Left (InequalityError "outer-strip column missing from reference material")) Right (M.lookup (u, v) source)
  lower <- sequence [point (fromRational u) v | u <- columns, v <- [-0.5, 0, 0.5]]
  upper <- sequence [point (negate (fromRational u)) v | u <- drop 1 columns, v <- [-0.5, 0, 0.5]]
  let upperId i = if i < 3 then i else length lower + i - 3
      cell i j = let a = 3 * i + j; b = 3 * (i + 1) + j in [(a, b, b + 1), (a, b + 1, a + 1)]
      faces = concat [cell i j | i <- [0 .. length columns - 2], j <- [0, 1]]
      mesh = Mesh (lower ++ upper) (faces ++ [(upperId a, upperId c, upperId b) | (a, b, c) <- faces])
      root h = let (a, b, _, _) = hingeVertices h in if a < 3 && b < 3 then h {hingeRole = SurfaceCrease (EdgeId 0), hingeRest = pi, hingeStiffness = 0.5} else h
      profile ps = [p | (u, p) <- zip (outerColumns Fine) ps, u `elem` columns]
  passive <- map root <$> adapt (buildPanelHinges (Bending 1 0.2) mesh)
  let reference = ClosedCrease mesh (replicate (length faces) (FaceId 0) ++ replicate (length faces) (FaceId 1)) passive [0, 1, 2] (profile (lowerProfile original)) (profile (upperProfile original))
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples mesh), abs (materialU p) <= 1 / 8 || abs (materialU p) == 1 / 2]
  controls <- if control == MatchedHolds then pure [] else map (if rule == OriginalTurns then boundaryOriginal else boundaryCandidate) <$> outerBoundaryMeasures choice reference
  pure (CoupledFixture reference {closedHinges = passive ++ controls} mesh pins)

-- | Reconstruct both loading rules from the same passive edges and measured
-- positions. This works before or after a solve and retains actual supports,
-- stiffnesses and derivatives for independent checks on the nonuniform grids.
outerBoundaryMeasures :: OuterMesh -> ClosedCrease -> Either InequalityError [BoundaryMeasure]
outerBoundaryMeasures choice reference = do
  preference <- bandPreference
  fmap concat $ forM [h | h <- closedHinges reference, hingeRole h == PanelBend] $ \h -> do
    let (a, b, c, d) = hingeVertices h
    p <- vertex a
    q <- vertex b
    r <- vertex c
    s <- vertex d
    let distance = abs (materialU p)
    case outerInterval choice distance of
      Just ((left, right), interval@(lo, hi)) | materialU p < 0 && materialU p == materialU q -> do
        let fullSpan = right - left
            actualSpan = (abs (materialU r - materialU p) + abs (materialU s - materialU p)) / 2
        unless (actualSpan == fullSpan) (Left (InequalityError "outer-strip band support disagrees with its neighboring triangles"))
        let covered = hi - lo
            fraction = covered / fullSpan
            spanWidth = abs (materialV p - materialV q)
            (bandStart, bandEnd) = bandBounds preference
            target = bandDesiredTurn preference * covered / (bandEnd - bandStart)
            stiffness = bandBendingWeight preference * spanWidth / covered
            old = h {hingeRole = BendControl, hingeRest = target, hingeStiffness = stiffness}
            candidate = if fraction == 1 then old else old {hingeRest = target / fraction, hingeStiffness = stiffness * fraction * fraction}
        (actual, _) <- adapt (hingeAngle h vertices)
        let cost spring = hingeStiffness spring * angleError actual (hingeRest spring) ^ (2 :: Int) / 2
            slope spring = hingeStiffness spring * angleError actual (hingeRest spring)
        pure [BoundaryMeasure old candidate interval fullSpan fraction distance (min (materialV p) (materialV q), max (materialV p) (materialV q)) actual (cost old) (cost candidate) (slope old) (slope candidate)]
      _ -> pure []
  where
    vertices = IM.fromList (zip [0 ..] (samples (closedMesh reference)))
    vertex i = maybe (Left (InequalityError ("outer-strip band lost vertex " <> tshow i))) Right (IM.lookup i vertices)

adapt :: (Explain e) => Either e a -> Either InequalityError a
adapt = first (InequalityError . explain)
