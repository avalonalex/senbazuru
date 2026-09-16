-- | Separate unequal boundary holds from an imposed bend preference on the
-- small two-panel sheet. A narrow strip beside the crease stays held on BOTH
-- sides: otherwise opening an outer grip can also open the nominally closed
-- crease. Only the outer edge is held at the other end, leaving both interiors
-- free. All controls share that boundary policy; they are compared with this
-- matched baseline, not the earlier outer-strip baseline.
--
-- The upper grip turns by 0.05 radians about the end of the held root strip.
-- The curl control instead adds angular springs at three named material lines,
-- preferring twice their original profile turn. Those are explicit experimental
-- loads, not newly authored creases or an inferred rest shape. Their strength
-- is per material line length, unchanged by refinement across that line.
-- Contact-off keeps exactly the curl controls and holds, isolating the effect
-- of contact; its crossing endpoint remains a diagnostic. See docs/glossary.md
-- for material coordinates, panels and crease angles.
module UnequalCrease (UnequalControl (..), unequalCrease, unequalCreaseWithWidth, unequalContactMode, panelChanges, BendBreakdown (..), ControlTurn (..), bendBreakdown) where

import ClosedCrease
import Control.Monad (forM, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import FoldBending
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

data UnequalControl = MatchedHolds | OpenUpperGrip | UpperCurl | CurlWithoutContact | CrossedHolds
  deriving stock (Eq, Show, Enum, Bounded)

unequalContactMode :: UnequalControl -> PairContactMode
unequalContactMode CurlWithoutContact = WithoutPairContact
unequalContactMode _ = EnforcePairOrder

unequalCrease :: Int -> UnequalControl -> Either InequalityError CoupledFixture
unequalCrease count = unequalCreaseWithWidth count 1

unequalCreaseWithWidth :: Int -> Int -> UnequalControl -> Either InequalityError CoupledFixture
unequalCreaseWithWidth count width control = do
  original <- coupledCreaseWithWidth count width BothTouching
  let reference = coupledReference original
      mesh = coupledSeed original
      held p = abs (materialU p) <= 0.125 || abs (materialU p) == 0.5
      moved p
        | control == OpenUpperGrip && materialU p <= -0.125 =
            let V3 x y z = position p
                a = 0.05
             in p {position = V3 (0.125 + cos a * (x - 0.125) - sin a * z) y (sin a * (x - 0.125) + cos a * z)}
        | control == CrossedHolds && abs (materialU p) == 0.25 =
            let V3 x y z = position p
             in p {position = V3 x y (z + signum (materialU p) * 0.001)}
        | otherwise = p
      seed = mesh {samples = map moved (samples mesh)}
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples seed), held p || control == CrossedHolds && abs (materialU p) == 0.25]
      vertices = IM.fromList (zip [0 ..] (samples mesh))
      vertex i = maybe (Left (InequalityError ("unequal control lost material vertex " <> tshow i))) Right (IM.lookup i vertices)
  springs <-
    if control `elem` [UpperCurl, CurlWithoutContact]
      then fmap concat $ forM (closedHinges reference) $ \h -> do
        let (a, b, _, _) = hingeVertices h
        p <- vertex a
        q <- vertex b
        if hingeRole h == PanelBend && materialU p == materialU q && materialU p `elem` [-0.125, -0.25, -0.375]
          then do
            (angle, _) <- first (InequalityError . explain) (hingeAngle h vertices)
            pure [h {hingeRole = BendControl, hingeRest = 2 * angle, hingeStiffness = 8 * abs (materialV p - materialV q)}]
          else pure []
      else pure []
  pure original {coupledReference = reference {closedHinges = closedHinges reference ++ springs}, coupledSeed = seed, coupledPins = pins}

-- | Passive energy resists bending inside an uncreased panel. Imposed energy
-- comes from the extra upper springs, not the material itself. Their sum is
-- the panel/control quantity reported by 'bendingEnergy'; neither includes
-- the original shared crease. These are illustrative energy units.
data BendBreakdown = BendBreakdown
  { lowerPassiveEnergy :: !Double,
    upperPassiveEnergy :: !Double,
    imposedBendEnergy :: !Double,
    controlTurns :: ![ControlTurn]
  }
  deriving stock (Eq, Show)

-- | One width segment of an imposed line. Angles are signed radians, zero
-- means coplanar triangles, and the preferred angle is a load rather than an
-- achieved fold. Keep segments separate so a widthwise variation is visible.
-- The passive spring at the same edge stays present underneath the control;
-- its stiffness changes with triangle shape even when control strength stays
-- fixed. Reporting both makes that competition inspectable.
data ControlTurn = ControlTurn
  { turnVertices :: !(Int, Int, Int, Int),
    turnU :: !Double,
    turnVRange :: !(Double, Double),
    turnActual :: !Double,
    turnPreferred :: !Double,
    turnPassiveStiffness :: !Double,
    turnImposedStiffness :: !Double,
    turnPassiveEnergy :: !Double,
    turnImposedEnergy :: !Double
  }
  deriving stock (Eq, Show)

-- | Measure the existing springs without changing the objective or solving
-- again. A missing passive partner is an error, never an apparent zero cost.
bendBreakdown :: CoupledFixture -> MaterialMesh -> Either InequalityError BendBreakdown
bendBreakdown fixture mesh = do
  checkCoupledMaterial fixture mesh
  passive <- forM [h | h <- hinges, hingeRole h == PanelBend] $ \h -> do
    let (a, b, _, _) = hingeVertices h
    p <- vertex a
    q <- vertex b
    e <- energy [h]
    pure (materialU p + materialU q, e)
  imposed <- energy [h | h <- hinges, hingeRole h == BendControl]
  turns <- forM [h | h <- hinges, hingeRole h == BendControl] $ \h -> do
    let (a, b, _, _) = hingeVertices h
    p <- vertex a
    q <- vertex b
    partner <- case [s | s <- hinges, hingeRole s == PanelBend, hingeVertices s == hingeVertices h] of
      [s] -> Right s
      _ -> Left (InequalityError ("expected one passive spring under bend control " <> tshow (a, b)))
    (actual, _) <- first (InequalityError . explain) (hingeAngle h vertices)
    passiveEnergy <- energy [partner]
    imposedEnergy <- energy [h]
    pure (ControlTurn (hingeVertices h) (materialU p) (min (materialV p) (materialV q), max (materialV p) (materialV q)) actual (hingeRest h) (hingeStiffness partner) (hingeStiffness h) passiveEnergy imposedEnergy)
  pure (BendBreakdown (sum [e | (u, e) <- passive, u > 0]) (sum [e | (u, e) <- passive, u < 0]) imposed turns)
  where
    hinges = closedHinges (coupledReference fixture)
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    vertex i = maybe (Left (InequalityError ("bend diagnostic lost material vertex " <> tshow i))) Right (IM.lookup i vertices)
    energy hs = snd <$> first (InequalityError . explain) (bendingEnergy hs mesh)

-- | Compare the same material points, including holds, on each panel. The
-- first value is lower, the second upper; a missing point is never a zero.
panelChanges :: MaterialMesh -> MaterialMesh -> Either InequalityError (Double, Double)
panelChanges before after = do
  unless (triangles before == triangles after && map sampleMaterial (samples before) == map sampleMaterial (samples after)) (Left (InequalityError "panel response needs the same material and triangles"))
  let change side = maximum (0 : [norm (position a ^-^ position b) | (a, b) <- zip (samples before) (samples after), signum (materialU a) == side])
  pure (change 1, change (-1))
