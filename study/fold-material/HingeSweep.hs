-- | Check a specified rigid flap rotation between two poses.
-- A hinge is a fixed line about which the selected material vertices rotate.
-- Each triangle must belong wholly to the rotating part or the stationary part;
-- their shared vertices must lie on that line. This keeps the sheet connected
-- without stretching it by interpolating positions between poses.
--
-- A rotating point has the form centre + u*cos(angle) + v*sin(angle). Along
-- any measuring direction its extreme positions over an angular interval are
-- the endpoint values AND any sine-wave extrema inside it. If two triangles'
-- projection ranges are separated, they cannot meet anywhere in that interval.
-- Otherwise subdivide; a work limit returns Unresolved, never Clear.
--
-- Triangles moving together keep their initial relative geometry. Across the
-- hinge, a stationary triangle's plane may separate the moving interior
-- throughout the interval: touching on their shared hinge is legal. That
-- shortcut requires the hinge to lie in the plane, and checks that the two
-- hinge boundaries overlap only where they share material vertex ids.
-- We do not skip all pairs sharing a corner. Independent static triangle checks
-- supply collision witnesses, not a supposed first impact time.
--
-- This is a numerical interval check for ONE fixed-axis rotation, with a 1e-10
-- separation guard on the study's unit sheets. It is not formally rounded
-- interval arithmetic, arbitrary bending, thickness, or a solver motion model.
module HingeSweep
  ( HingeSweep,
    SweepSettings (..),
    defaultSweepSettings,
    SweepOutcome (..),
    SweepCheck (..),
    SweepError (..),
    prepareSweep,
    sweepStart,
    sweepMeshAt,
    checkSweep,
    sinusoidRange,
  )
where

import Control.Monad (filterM, unless, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (tails)
import Data.Set qualified as S
import PanelContact qualified as Panel
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..), Triangle)

data Orbit = Fixed !V3 | Turning !V3 !V3 !V3
  deriving stock (Eq, Show)

data HingeSweep = HingeSweep !MaterialMesh !(IM.IntMap Orbit) ![Bool] !V3 !V3 !Double
  deriving stock (Eq, Show)

data SweepSettings = SweepSettings {sweepDepth :: !Int, sweepBudget :: !Int}
  deriving stock (Eq, Show)

defaultSweepSettings :: SweepSettings
defaultSweepSettings = SweepSettings 20 4096

data SweepOutcome = SweepClear | SweepCollision !Double ![(Int, Int)] | SweepUnresolved !Double !Double ![(Int, Int)]
  deriving stock (Eq, Show)

data SweepCheck = SweepCheck {sweepOutcome :: !SweepOutcome, sweepIntervals :: !Int}
  deriving stock (Eq, Show)

data SweepError
  = InvalidSweepAxis
  | InvalidSweepAngle
  | InvalidSweepSettings
  | InvalidSweepProgress
  | InvalidSweepRange
  | InvalidSweepVertex !Int
  | InvalidSweepTriangle !Int
  | MissingSweepVertex !Int
  | NonRigidSweepTriangle !Int
  | SweepGeometry !Panel.ContactError
  deriving stock (Eq, Show)

instance Explain SweepError where
  explain InvalidSweepAxis = "hinge sweep needs a finite origin and nonzero finite direction"
  explain InvalidSweepAngle = "hinge sweep needs finite signed angular travel of at most one full turn"
  explain InvalidSweepSettings = "hinge sweep needs a depth from 0 to 30 and a positive interval budget"
  explain InvalidSweepRange = "sinusoid range needs finite coefficients and angles within one full turn of zero"
  explain InvalidSweepProgress = "hinge sweep progress must lie between zero and one"
  explain (InvalidSweepVertex i) = "hinge sweep vertex " <> tshow i <> " has a non-finite material or spatial coordinate"
  explain (InvalidSweepTriangle i) = "hinge sweep triangle " <> tshow i <> " is missing or degenerate"
  explain (MissingSweepVertex i) = "hinge sweep refers to missing material vertex " <> tshow i
  explain (NonRigidSweepTriangle i) = "hinge sweep would stretch triangle " <> tshow i <> "; a triangle cannot mix stationary and moving vertices away from the hinge"
  explain (SweepGeometry err) = explain err

-- | Origin, direction, signed angular travel in radians, moving vertex ids,
-- and starting mesh. Vertices within 1e-12 of the hinge stay exactly fixed.
-- The constructor is hidden so these rigidity checks cannot be bypassed.
prepareSweep :: V3 -> V3 -> Double -> [Int] -> MaterialMesh -> Either SweepError HingeSweep
prepareSweep origin direction angle moving mesh = do
  unless (finitePoint origin && finitePoint direction && finite (norm direction) && norm direction > 1e-12) (Left InvalidSweepAxis)
  unless (finite angle && abs angle <= 2 * pi) (Left InvalidSweepAngle)
  when (null (triangles mesh)) (Left (InvalidSweepTriangle 0))
  let axis = (1 / norm direction) *^ direction
      vertices = IM.fromList (zip [0 ..] (samples mesh))
      selected = S.fromList moving
      vertex i = maybe (Left (MissingSweepVertex i)) Right (IM.lookup i vertices)
      orbit i sample = do
        let p = position sample
            V2 u v = sampleMaterial sample
            delta = p ^-^ origin
            radial = delta ^-^ (dot delta axis *^ axis)
        unless (finitePoint p && all finite [u, v] && finite (norm radial)) (Left (InvalidSweepVertex i))
        pure $ if S.notMember i selected || norm radial <= 1e-12 then Fixed p else Turning (p ^-^ radial) radial (cross axis radial)
  mapM_ vertex moving
  orbits <- IM.traverseWithKey orbit vertices
  let onAxis i = do
        sample <- vertex i
        let delta = position sample ^-^ origin
        pure (norm (cross axis delta) <= 1e-12)
      triangle (i, ids) = do
        ps <- mapM (fmap position . vertex) (corners ids)
        unless (finitePoint (normal ps) && finite (norm (normal ps)) && norm (normal ps) > 1e-14) (Left (InvalidSweepTriangle i))
        offAxis <- filterM (fmap not . onAxis) (corners ids)
        let flags = map (`S.member` selected) offAxis
        unless (and flags || all not flags) (Left (NonRigidSweepTriangle i))
        pure (or flags && angle /= 0)
  turning <- mapM triangle (zip [0 ..] (triangles mesh))
  pure (HingeSweep mesh orbits turning origin axis angle)

sweepStart :: HingeSweep -> MaterialMesh
sweepStart (HingeSweep mesh _ _ _ _ _) = mesh

sweepMeshAt :: HingeSweep -> Double -> Either SweepError MaterialMesh
sweepMeshAt (HingeSweep mesh orbits _ _ _ angle) progress = do
  unless (finite progress && progress >= 0 && progress <= 1) (Left InvalidSweepProgress)
  let sample (i, original) = case IM.lookup i orbits of
        Nothing -> Left (MissingSweepVertex i)
        Just path -> Right original {position = orbitAt path (progress * angle)}
  if progress == 0
    then pure mesh
    else do
      current <- mapM sample (zip [0 ..] (samples mesh))
      pure mesh {samples = current}

orbitAt :: Orbit -> Double -> V3
orbitAt (Fixed p) _ = p
orbitAt (Turning centre u v) angle = centre ^+^ (cos angle *^ u) ^+^ (sin angle *^ v)

-- | Range of a*cos(theta)+b*sin(theta), including interior extrema.
-- Coefficients and angles must be finite, with angles within one turn of zero.
-- Negative travel is handled by sorting the interval, not changing its sign.
sinusoidRange :: Double -> Double -> Double -> Double -> Either SweepError (Double, Double)
sinusoidRange a b from to = do
  unless (all finite [a, b, from, to, a * a + b * b] && abs from <= 2 * pi && abs to <= 2 * pi) (Left InvalidSweepRange)
  pure (rangeWithin a b from to)

rangeWithin :: Double -> Double -> Double -> Double -> (Double, Double)
rangeWithin a b from to = (minimum values, maximum values)
  where
    lo = min from to
    hi = max from to
    radius = sqrt (a * a + b * b)
    phase = atan2 b a
    contains offset = any (\k -> let x = offset + fromIntegral k * 2 * pi in x >= lo && x <= hi) [floor ((lo - offset) / (2 * pi)) .. ceiling ((hi - offset) / (2 * pi)) :: Int]
    values = [a * cos lo + b * sin lo, a * cos hi + b * sin hi] ++ [radius | contains phase] ++ [-radius | contains (phase + pi)]

checkSweep :: SweepSettings -> HingeSweep -> Either SweepError SweepCheck
checkSweep settings sweep@(HingeSweep mesh orbits turning hingeOrigin hingeAxis angle) = do
  unless (sweepDepth settings >= 0 && sweepDepth settings <= 30 && sweepBudget settings > 0) (Left InvalidSweepSettings)
  initialBad <- collisions mesh pairs
  if not (null initialBad)
    then pure (SweepCheck (SweepCollision 0 initialBad) 0)
    else do
      final <- sweepMeshAt sweep 1
      finalBad <- collisions final pairs
      if not (null finalBad)
        then pure (SweepCheck (SweepCollision 1 finalBad) 0)
        else walk 0 (sweepDepth settings) 0 1 movingPairs
  where
    indexed = zip3 [0 ..] (triangles mesh) turning
    pairs = [(i, j) | (i, _, _) : rest <- tails indexed, (j, _, _) <- rest]
    -- All other pairs have constant relative geometry, checked above.
    movingPairs = [(i, j) | (i, _, a) : rest <- tails indexed, (j, _, b) <- rest, a /= b]
    topology = IM.fromList (zip [0 ..] (triangles mesh))
    ids i = maybe [] corners (IM.lookup i topology)
    pointAt t i = maybe (V3 0 0 0) (`orbitAt` (t * angle)) (IM.lookup i orbits)
    points t i = map (pointAt t) (ids i)
    guardDistance = 1e-10
    projected axis origin lo hi i = case IM.lookup i orbits of
      Just (Fixed p) -> let d = dot axis (p ^-^ origin) in (d, d)
      Just (Turning c u v) -> let d = dot axis (c ^-^ origin); (a, b) = rangeWithin (dot axis u) (dot axis v) (lo * angle) (hi * angle) in (d + a, d + b)
      Nothing -> (negate (1 / 0), 1 / 0)
    separated lo hi (i, j) = any along axes || hingeSide i j || hingeSide j i
      where
        as = points ((lo + hi) / 2) i
        bs = points ((lo + hi) / 2) j
        na = normal as
        nb = normal bs
        es = edges as
        fs = edges bs
        axes = [unit v | v <- [na, nb, V3 1 0 0, V3 0 1 0, V3 0 0 1] ++ [cross e f | e <- es, f <- fs] ++ map (cross na) es ++ map (cross nb) fs, norm v > 1e-12]
        along axis =
          let origin = pointAt 0 (minimum (ids i))
              ar = map (projected axis origin lo hi) (ids i)
              br = map (projected axis origin lo hi) (ids j)
           in maximum (map snd ar) + guardDistance < minimum (map fst br) || maximum (map snd br) + guardDistance < minimum (map fst ar)
        -- The stationary triangle DEFINES this plane; no epsilon test guesses
        -- that another triangle lies in it. Shared vertices are fixed on the
        -- hinge by preparation. Off-hinge vertices need strict gaps; boundary
        -- intervals must overlap only along the shared material. A corner
        -- attachment alone does NOT put the rotation axis in this plane.
        hingeSide fixed moving =
          let common = filter (`elem` ids fixed) (ids moving)
              onHinge v = norm (cross hingeAxis (pointAt 0 v ^-^ hingeOrigin)) <= 1e-12
              fixedBoundary = filter onHinge (ids fixed)
              movingBoundary = filter onHinge (ids moving)
              fixedInterior = filter (not . onHinge) (ids fixed)
              movingInterior = filter (not . onHinge) (ids moving)
              stationary = all (\v -> case IM.lookup v orbits of Just (Fixed _) -> True; _ -> False) (ids fixed)
              oneSide ranges = all ((> guardDistance) . fst) ranges || all ((< negate guardDistance) . snd) ranges
           in case common of
                anchor : _
                  | stationary && not (null movingInterior) && not (null fixedInterior) && not (null fixedBoundary) && not (null movingBoundary) ->
                      let axis = unit (normal (points 0 fixed))
                          origin = pointAt 0 anchor
                          ranges = map (projected axis origin lo hi) movingInterior
                          acrossHinge = unit (cross axis hingeAxis)
                          fixedSides = [let d = dot acrossHinge (pointAt 0 v ^-^ origin) in (d, d) | v <- fixedInterior]
                          extent vs = let ds = map (\v -> dot hingeAxis (pointAt 0 v ^-^ origin)) vs in (minimum ds, maximum ds)
                          (fa, fb) = extent fixedBoundary
                          (ma, mb) = extent movingBoundary
                          (ca, cb) = extent common
                          sharedOnly = max fa ma >= ca && min fb mb <= cb
                       in abs (dot axis hingeAxis) <= 1e-12 && oneSide ranges && oneSide fixedSides && sharedOnly
                _ -> False
    collisions current candidates = do
      let vertices = IM.fromList (zip [0 ..] (samples current))
          panel i = Panel.Panel (tshow i) [position p | v <- ids i, Just p <- [IM.lookup v vertices]]
          inspect pair@(i, j) = do
            report <- first SweepGeometry (Panel.checkPanelContact (V3 0 0 1) [] [panel i, panel j])
            pure [pair | not (Panel.contactPassed report)]
      concat <$> mapM inspect candidates
    walk count depth lo hi candidates
      | count >= sweepBudget settings = pure (SweepCheck (SweepUnresolved lo hi candidates) count)
      | otherwise = do
          let remaining = filter (not . separated lo hi) candidates
              midpoint = (lo + hi) / 2
              used = count + 1
          if null remaining
            then pure (SweepCheck SweepClear used)
            else do
              middle <- sweepMeshAt sweep midpoint
              bad <- collisions middle remaining
              if not (null bad)
                then pure (SweepCheck (SweepCollision midpoint bad) used)
                else
                  if depth == 0
                    then pure (SweepCheck (SweepUnresolved lo hi remaining) used)
                    else do
                      left <- walk used (depth - 1) lo midpoint remaining
                      case sweepOutcome left of
                        SweepClear -> walk (sweepIntervals left) (depth - 1) midpoint hi remaining
                        _ -> pure left

corners :: Triangle -> [Int]
corners (a, b, c) = [a, b, c]

normal :: [V3] -> V3
normal [a, b, c] = cross (b ^-^ a) (c ^-^ a)
normal _ = V3 0 0 0

edges :: [V3] -> [V3]
edges ps = zipWith (^-^) (drop 1 ps ++ take 1 ps) ps

unit :: V3 -> V3
unit p = (1 / norm p) *^ p

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

finitePoint :: V3 -> Bool
finitePoint (V3 x y z) = all finite [x, y, z]
