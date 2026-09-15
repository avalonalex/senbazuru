-- | Release BOTH interiors beside one shared crease. Only the crease and
-- outer strips are held; there are no equations welding the touching layers.
-- Contact comes from their current triangles, along the known z order.
-- This isolates moving contact partners without claiming a general crane solve.
--
-- A feasibility repair moves free upper vertices upward and free lower
-- vertices downward by the same amount. Exact overlap weights give the smallest
-- such common displacement at fixed x/y. Held and shared crease vertices stay
-- unchanged. Directed rounding goes outward on each side, and the actual
-- stored mesh must pass an exact recheck. This symmetric choice of repair is
-- explicit numerical policy, not physical thickness or a prescribed motion.
module CoupledCrease
  ( CoupledControl (..),
    CoupledFixture (..),
    coupledCrease,
    checkCoupledMaterial,
    repairCoupled,
    solveCoupled,
    coupledSurface,
  )
where

import ClosedCrease
import ContactQuadratic
import Control.Monad (foldM, forM, unless)
import CreaseInequality
import CreasePairContact
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (fromMaybe)
import FoldRelaxation (Settings (..), maxLengthError)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

data CoupledControl = BothTouching | BothPenetrating | BothTiny | IncompatibleHolds deriving stock (Eq, Show, Enum, Bounded)

data CoupledFixture = CoupledFixture
  { coupledReference :: !ClosedCrease,
    coupledSeed :: !MaterialMesh,
    coupledPins :: !(IM.IntMap V3)
  }
  deriving stock (Show)

coupledCrease :: Int -> CoupledControl -> Either InequalityError CoupledFixture
coupledCrease count control = do
  reference <- adapt (closedCrease count BentTouching)
  let original = closedMesh reference
      held p = materialU p == 0 || abs (materialU p) >= 0.375
      magnitude = case control of BothTouching -> 0; BothTiny -> 1e-8; _ -> 0.001
      moved p
        | held p = p
        | otherwise = p {position = position p ^-^ (outward p * magnitude * sin (pi * abs (materialU p) / 0.5)) *^ V3 0 0 1}
      seed = original {samples = map moved (samples original)}
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples seed), held p || control == IncompatibleHolds && abs (materialU p) == 0.25]
  pure (CoupledFixture reference seed pins)

outward :: MaterialSample -> Double
outward p = if materialU p < 0 then 1 else -1

checkCoupledMaterial :: CoupledFixture -> MaterialMesh -> Either InequalityError ()
checkCoupledMaterial fixture mesh = do
  let reference = closedMesh (coupledReference fixture)
      actual = IM.fromList (zip [0 ..] (map position (samples mesh)))
  unless (triangles mesh == triangles reference && map sampleMaterial (samples mesh) == map sampleMaterial (samples reference)) (Left (InequalityError "coupled correction must preserve material and triangle identities"))
  unless (all (\(i, p) -> IM.lookup i actual == Just p) (IM.toList (coupledPins fixture))) (Left (InequalityError "coupled correction moved a held vertex"))
  unless (all (`IM.member` coupledPins fixture) (closedRoot (coupledReference fixture))) (Left (InequalityError "the small coupled experiment requires all shared crease vertices held"))

repairCoupled :: CoupledFixture -> MaterialMesh -> Either InequalityError FeasibleRepair
repairCoupled fixture mesh = do
  checkCoupledMaterial fixture mesh
  audit <- adapt (auditPairContact (closedOwners (coupledReference fixture)) mesh)
  let signs = IM.fromList [(i, toRational (outward p)) | (i, p) <- zip [0 ..] (samples mesh), IM.notMember i (coupledPins fixture)]
      weight w = sum (IM.intersectionWith (*) signs (pairWeights w))
  amounts <- forM [w | w <- pairWitnesses audit, pairGap w < 0] $ \w -> do
    let movable = weight w
    unless (movable > 0) (Left (InequalityError ("held contact vertices " <> tshow (IM.keys (pairWeights w)) <> " require a negative gap of " <> num (fromRational (pairGap w)))))
    pure (negate (pairGap w) / movable)
  let amount = maximum (0 : amounts)
  moved <- forM (zip [0 ..] (samples mesh)) $ \(i, p) -> case IM.lookup i signs of
    Nothing -> pure (p, 0)
    Just sign -> do
      let V3 x y z = position p
          target = toRational z + sign * amount
      height <- if sign > 0 then ceilingDouble target else negate <$> ceilingDouble (negate target)
      pure (p {position = V3 x y height}, fromRational (abs (toRational height - target)))
  let result = mesh {samples = map fst moved}
  final <- adapt (auditPairContact (closedOwners (coupledReference fixture)) result)
  unless (pairMinimum final >= 0) (Left (InequalityError "the coupled repair failed its exact stored-coordinate check"))
  pure (FeasibleRepair result amount (maximum (0 : map snd moved)))

solveCoupled :: Settings -> CoupledFixture -> Either InequalityError InequalityResult
solveCoupled settings fixture = do
  unless (iterationLimit settings > 0 && finite (lengthTolerance settings) && lengthTolerance settings > 0) (Left (InequalityError "coupled correction needs positive finite settings"))
  initial <- repairCoupled fixture (coupledSeed fixture)
  (mesh, history, settled) <- foldM stage (repairedMesh initial, [], False) [1e2, 1e4, 1e6, 1e8]
  pure (InequalityResult initial mesh history settled)
  where
    reference = coupledReference fixture
    pins = coupledPins fixture
    free i = IM.notMember i pins
    ids = [i | (i, _) <- zip [0 ..] (samples (coupledSeed fixture)), free i]
    signs = IM.fromList [(i, toRational (outward p)) | (i, p) <- zip [0 ..] (samples (coupledSeed fixture)), free i]
    rows = materialRows (closedHinges reference) pins
    energy weight mesh = do
      measured <- rows weight mesh
      let value = sum [r * r | (_, r) <- measured]
      unless (finite value) (Left (InequalityError "the coupled material objective is non-finite"))
      pure value
    stage (mesh, history, _) weight = advance weight mesh history 0
    advance weight mesh history count
      | count >= iterationLimit settings = pure (mesh, history, False)
      | otherwise = do
          material <- rows weight mesh
          gaps <- adapt (auditPairContact (closedOwners reference) mesh)
          let constraints =
                [ (IM.map (\w -> fromRational (w / movable) *^ V3 (fromRational x) (fromRational y) (fromRational z)) weights, fromRational (pairGap witness / movable))
                  | witness <- pairWitnesses gaps,
                    let weights = IM.filterWithKey (\i _ -> free i) (pairWeights witness),
                    let movable = sum (IM.intersectionWith (*) signs weights),
                    movable > 0,
                    let (x, y, z) = pairNormal witness
                ]
          (direction, quadratic) <- adapt (constrainedStep 2000 1e-3 ids material constraints)
          before <- energy weight mesh
          let candidate scale = mesh {samples = [p {position = position p ^+^ (scale *^ IM.findWithDefault (V3 0 0 0) i direction)} | (i, p) <- zip [0 ..] (samples mesh)]}
              repair scale = repairCoupled fixture (candidate scale)
          full <- repair 1
          let movement = maximum (0 : [norm (position a ^-^ position b) | (a, b) <- zip (samples mesh) (samples (repairedMesh full))])
              settled = quadraticConverged quadratic && movement <= 1e-7 && (weight < 1e8 || maxLengthError mesh <= lengthTolerance settings)
              search scale remaining = case repair scale of
                Left _ -> if remaining == 0 then pure Nothing else search (scale / 2) (remaining - 1)
                Right fixed -> do
                  after <- energy weight (repairedMesh fixed)
                  if after < before then pure (Just (scale, fixed, after)) else if remaining == 0 then pure Nothing else search (scale / 2) (remaining - 1)
          trial <- if settled || not (quadraticConverged quadratic) then pure Nothing else search 1 (30 :: Int)
          let (scale, fixed, after) = fromMaybe (0, FeasibleRepair mesh 0 0, before) trial
              next = repairedMesh fixed
              accepted = scale > 0
          gap <- adapt (auditPairContact (closedOwners reference) next)
          let record = InequalityStep (length history + 1) weight quadratic movement scale (fromRational (commonLift fixed)) (maxRoundingLift fixed) before after (pairMinimum gap) (maxLengthError next) accepted settled
              history' = history ++ [record]
          if settled || not accepted then pure (next, history', settled) else advance weight next history' (count + 1)

coupledSurface :: CoupledFixture -> MaterialMesh -> Either InequalityError (Surface V2)
coupledSurface fixture mesh = do
  checkCoupledMaterial fixture mesh
  _ <- adapt (auditPairContact (closedOwners (coupledReference fixture)) mesh)
  adapt (closedSurface (coupledReference fixture) {closedMesh = mesh})

adapt :: (Explain e) => Either e a -> Either InequalityError a
adapt = first (InequalityError . explain)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)
