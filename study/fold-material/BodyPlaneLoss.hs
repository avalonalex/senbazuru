-- | Account for distance to a moving plane along a saved numerical trial.
-- The triangle centroid is our reference point. Moving that reference changes
-- the individual terms, so these are geometric accounting terms, not forces
-- or independently possible paper motions. Their sum is the signed distance.
--
-- Write r = vertex - centroid and n for the unit plane normal. A finite change
-- obeys d-d0 = n0 dot dr + dn dot r0 + dn dot dr. The linear guard includes
-- relative motion and the initial rate of normal rotation, but misses their
-- product and the normal's nonlinear remainder. Normalization is included in
-- both derivatives. Original winding supplies the sign throughout.
--
-- The saved trial can differ from the exact arithmetic path by rounding. Keep
-- that contribution and the final reconciliation residual separate; do not
-- turn the last floating-point digits into a claim about physical motion.
-- See docs/notes/body-plane-loss.md and docs/glossary.md.
module BodyPlaneLoss (PlanePose (..), PlaneLoss (..), PlaneLossError (..), decomposePlane) where

import Control.Monad (unless)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry.V3 (V3, cross)
import Senbazuru.Geometry.VectorSpace

-- | One measured vertex and the original ordered triangle vertices.
data PlanePose = PlanePose V3 V3 V3 V3 deriving stock (Eq, Show)

data PlaneLoss = PlaneLoss
  { initialDistance :: !Double,
    actualDistance :: !Double,
    linearDistance :: !Double,
    quadraticDistance :: !Double,
    relativeLinear :: !Double,
    rotationLinear :: !Double,
    rotationRemainder :: !Double,
    motionInteraction :: !Double,
    relativeRounding :: !Double,
    reconciliationError :: !Double,
    rotationSecondOrder :: !Double,
    interactionSecondOrder :: !Double,
    normalTurn :: !Double,
    startNormal :: !V3,
    trialNormal :: !V3,
    normalDerivative :: !V3,
    normalQuadratic :: !V3,
    startRelative :: !V3,
    trialRelative :: !V3,
    relativeDerivative :: !V3
  }
  deriving stock (Eq, Show)

data PlaneLossError = InvalidPlanePose | InvalidPlaneFraction deriving stock (Eq, Show)

instance Explain PlaneLossError where
  explain InvalidPlanePose = "plane-distance accounting needs finite points and nondegenerate start and trial triangles"
  explain InvalidPlaneFraction = "plane-distance accounting needs a finite trial fraction between zero and one"

-- | The full proposal supplies the direction; the last argument is the actual
-- saved trial. This function measures it; it does not generate or accept it.
decomposePlane :: PlanePose -> PlanePose -> Double -> PlanePose -> Either PlaneLossError PlaneLoss
decomposePlane before proposal fraction after = do
  unless (finite fraction && fraction >= 0 && fraction <= 1) (Left InvalidPlaneFraction)
  unless (all (finite . norm) (points before ++ points proposal ++ points after)) (Left InvalidPlanePose)
  n0 <- normal before
  ns <- normal after
  let (e, f, r0) = relative before
      (eFull, fFull, rFull) = relative proposal
      (_, _, rs) = relative after
      de = eFull ^-^ e
      df = fFull ^-^ f
      dr = rFull ^-^ r0
      area = norm (cross e f)
      q1 = (1 / area) *^ (cross de f ^+^ cross e df)
      q2 = (1 / area) *^ cross de df
      alpha = dot n0 q1
      beta = dot n0 q2 + (dot q1 q1 - alpha * alpha) / 2
      n1 = q1 ^-^ alpha *^ n0
      -- Coefficient of s^2, i.e. half of the second derivative.
      n2 = q2 ^-^ alpha *^ q1 ^+^ (alpha * alpha - beta) *^ n0
      dn = ns ^-^ n0
      drSaved = rs ^-^ r0
      d0 = dot n0 r0
      actual = dot ns rs
      move = fraction * dot n0 dr
      turn = fraction * dot n1 r0
      remainder = dot (dn ^-^ fraction *^ n1) r0
      interaction = dot dn drSaved
      rounding = dot n0 (drSaved ^-^ fraction *^ dr)
      linear = d0 + move + turn
      rotation2 = fraction * fraction * dot n2 r0
      interaction2 = fraction * fraction * dot n1 dr
      quadratic = linear + rotation2 + interaction2
      residual = actual - d0 - (move + turn + remainder + interaction + rounding)
      angle = atan2 (norm (cross n0 ns)) (dot n0 ns)
      result = PlaneLoss d0 actual linear quadratic move turn remainder interaction rounding residual rotation2 interaction2 angle n0 ns n1 n2 r0 rs dr
  unless (all finite [d0, actual, linear, quadratic, move, turn, remainder, interaction, rounding, residual, rotation2, interaction2, angle]) (Left InvalidPlanePose)
  pure result
  where
    normal pose = do
      let (e, f, _) = relative pose; n = cross e f; area = norm n
      unless (finite area && area > 1e-12) (Left InvalidPlanePose)
      pure ((1 / area) *^ n)

relative :: PlanePose -> (V3, V3, V3)
relative (PlanePose p a b c) = (b ^-^ a, c ^-^ a, p ^-^ ((1 / 3) *^ (a ^+^ b ^+^ c)))

points :: PlanePose -> [V3]
points (PlanePose p a b c) = [p, a, b, c]

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
