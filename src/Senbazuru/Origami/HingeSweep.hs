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
-- 'checkSweepWithFlatEndpoints' also admits a one-sided flat contact. The
-- stationary plane must contain the hinge, and a coplanar endpoint makes each
-- moving point's signed distance a multiple of sin(theta - thetaEndpoint).
-- A half-turn or shorter has no interior zero; common hinge boundaries still
-- need matching material ids. Its endpoint orders are returned explicitly.
-- Coplanarity is recognized within 64 machine epsilons on a unit sheet
-- (about 1.42e-14), to accommodate the residual of sin(pi). This is a numerical
-- convention, not an exact proof for arbitrarily small gaps. No time interval
-- or unrelated pair is omitted.
--
-- 'checkSweepWithRigidContacts' additionally accepts explicitly named pairs
-- that start coplanar and undergo the SAME rigid motion (or both stay still).
-- Their relative geometry cannot change, so contact persists without crossing.
-- The caller must supply and retain the layer order; this geometric check
-- cannot choose which side of coincident paper is above. Merely naming a pair
-- does not exempt it: different motions or noncoplanar geometry are refused,
-- and every pair outside that contact retains its ordinary interval check.
-- A declared stack also supports an unjoined edge resting on the hinge: its
-- contact with the opposite triangle must fit inside a real shared hinge of
-- a declared partner. This only authorizes the boundary. The stationary plane
-- must still separate the moving interior, just as for a shared crease.
-- Coincident corners keep their distinct material ids; no seam is welded.
-- 'checkSweepWithLayerContacts' additionally accepts a resting hinge across
-- another panel's interior. The moving interior must leave that panel's plane
-- to one side for the whole turn. This does not require the stationary panel
-- to lie on one side of the hinge: a wing can rest over the middle of another
-- wing. The returned departure side still needs the caller's order check.
--
-- This is a numerical interval check for ONE fixed-axis rotation, with a 1e-10
-- separation guard on unit sheets. It is not formally rounded
-- interval arithmetic, arbitrary bending, thickness, or a solver motion model.
module Senbazuru.Origami.HingeSweep
  ( HingeSweep,
    SweepSettings (..),
    defaultSweepSettings,
    SweepOutcome (..),
    SweepCheck (..),
    EndpointContact (..),
    SweepError (..),
    prepareSweep,
    sweepStart,
    sweepMeshAt,
    checkSweep,
    checkSweepWithFlatEndpoints,
    checkSweepWithRigidContacts,
    checkSweepWithLayerContacts,
    sinusoidRange,
  )
where

import Control.Monad (filterM, unless, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (tails)
import Data.Map.Strict qualified as M
import Data.Maybe (listToMaybe)
import Data.Set qualified as S
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact qualified as Panel
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

data SweepCheck = SweepCheck {sweepOutcome :: !SweepOutcome, sweepIntervals :: !Int, sweepEndpointContacts :: ![EndpointContact]}
  deriving stock (Eq, Show)

-- | Overlapping triangles at an accepted endpoint. The sign names the side
-- of the stationary triangle's wound normal occupied just inside the motion.
-- It is geometric layer information, independent of the camera.
data EndpointContact = EndpointContact
  { contactProgress :: !Double,
    contactFixed :: !Int,
    contactMoving :: !Int,
    contactSide :: !Int
  }
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
  | InvalidRigidContact !Int !Int
  | InvalidRestingContact !Int !Int
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
  explain (InvalidRigidContact i j) = "persistent contact needs distinct coplanar triangles with the same rigid motion; got triangles " <> tshow i <> " and " <> tshow j
  explain (InvalidRestingContact i j) = "resting contact needs distinct initially coplanar triangles with different motions; got triangles " <> tshow i <> " and " <> tshow j
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
checkSweep = checkWithEndpoints False [] []

-- | Permit coplanar overlap only at a boundary of the motion, with a
-- one-sided approach/departure. The returned contacts supply its layer order.
-- Persistent touching pairs still fail. 'checkSweep' retains its strict
-- endpoint policy for callers without a way to carry layer information.
checkSweepWithFlatEndpoints :: SweepSettings -> HingeSweep -> Either SweepError SweepCheck
checkSweepWithFlatEndpoints = checkWithEndpoints True [] []

-- | Permit declared coplanar contacts with unchanged relative geometry,
-- together with the one-sided flat endpoint rule. Pair indices refer to the
-- starting mesh's triangles. The caller owns the consistent layer ordering;
-- this function verifies coplanarity and common motion for every named pair.
-- A partner's shared hinge may support an unjoined stack boundary along that
-- same segment, provided the one-sided plane check also passes.
checkSweepWithRigidContacts :: SweepSettings -> [(Int, Int)] -> HingeSweep -> Either SweepError SweepCheck
checkSweepWithRigidContacts settings contacts = checkWithEndpoints True contacts [] settings

-- | In addition to rigid contacts, name initially coplanar layers that can
-- separate. A wing can lift while its hinge rests across another layer's
-- interior. The moving interior must still stay strictly on one side of that
-- layer's plane for the whole turn; only the stationary hinge may keep touching.
-- The caller must check the returned departure side against its initial order.
-- Declaring a pair does not exempt it from the plane or interval checks.
checkSweepWithLayerContacts :: SweepSettings -> [(Int, Int)] -> [(Int, Int)] -> HingeSweep -> Either SweepError SweepCheck
checkSweepWithLayerContacts settings rigid resting = checkWithEndpoints True rigid resting settings

checkWithEndpoints :: Bool -> [(Int, Int)] -> [(Int, Int)] -> SweepSettings -> HingeSweep -> Either SweepError SweepCheck
checkWithEndpoints allowEndpoints contacts resting settings sweep@(HingeSweep mesh orbits turning hingeOrigin hingeAxis angle) = do
  unless (sweepDepth settings >= 0 && sweepDepth settings <= 30 && sweepBudget settings > 0) (Left InvalidSweepSettings)
  mapM_ validateContact contacts
  mapM_ validateResting resting
  (initialBad, initialContacts) <- endpoint 0 mesh
  if not (null initialBad)
    then pure (SweepCheck (SweepCollision 0 initialBad) 0 [])
    else do
      final <- sweepMeshAt sweep 1
      (finalBad, finalContacts) <- endpoint 1 final
      if not (null finalBad)
        then pure (SweepCheck (SweepCollision 1 finalBad) 0 [])
        else do
          result <- walk 0 (sweepDepth settings) 0 1 movingPairs
          pure result {sweepEndpointContacts = [c | sweepOutcome result == SweepClear, c <- initialContacts ++ finalContacts]}
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
    -- This much smaller bound only recognizes a rounded coplanar endpoint.
    -- It does not enlarge the contact tolerance or skip a short time interval.
    endpointRoundoff = 64 * encodeFloat 1 (-52)
    rigidContacts = S.fromList [(min i j, max i j) | (i, j) <- contacts]
    restingContacts = S.fromList [(min i j, max i j) | (i, j) <- resting]
    validateResting (i, j) =
      let flags = IM.fromList (zip [0 ..] turning)
          inPlane a b = case points 0 a of
            origin : _ -> all (\p -> abs (dot (unit (normal (points 0 a))) (p ^-^ origin)) <= endpointRoundoff) (points 0 b)
            [] -> False
       in unless (i /= j && IM.member i flags && IM.member j flags && IM.lookup i flags /= IM.lookup j flags && inPlane i j && inPlane j i) (Left (InvalidRestingContact i j))
    validateContact (i, j) =
      let flags = IM.fromList (zip [0 ..] turning)
          inPlane a b = case points 0 a of
            origin : _ -> all (\p -> abs (dot (unit (normal (points 0 a))) (p ^-^ origin)) <= endpointRoundoff) (points 0 b)
            [] -> False
       in unless (i /= j && IM.member i flags && IM.member j flags && IM.lookup i flags == IM.lookup j flags && inPlane i j && inPlane j i) (Left (InvalidRigidContact i j))
    endpointPlanes = M.fromList [(pair, proof) | allowEndpoints, pair <- movingPairs, Just proof <- [endpointPlane pair]]
    endpointPlane (i, j) = listToMaybe [proof | (fixed, moving) <- [(i, j), (j, i)], t <- [0, 1], Just proof <- [oneSided t fixed moving]]
    oneSided t fixed moving =
      let n = unit (normal (points 0 fixed))
          origin = pointAt 0 (minimum (ids fixed))
          onHinge v = norm (cross hingeAxis (pointAt 0 v ^-^ hingeOrigin)) <= 1e-12
          stationary = all (\v -> case IM.lookup v orbits of Just (Fixed _) -> True; _ -> False) (ids fixed)
          rotating = all (\v -> case IM.lookup v orbits of Just Turning {} -> True; _ -> False) (filter (not . onHinge) (ids moving))
          interior = filter (not . onHinge) (ids moving)
          inPlane p = abs (dot n (p ^-^ origin)) <= endpointRoundoff
          derivative v = dot n (cross hingeAxis (pointAt t v ^-^ hingeOrigin))
          -- With the hinge and endpoint in the plane, signed distance is
          -- derivative * sin(theta - thetaEndpoint). On at most a half-turn
          -- this sine has no interior zero. Its sign inside the motion is
          -- the sign of travel away from that endpoint; no sampling is used.
          heights = [derivative v * signum (angle * (0.5 - t)) | v <- interior]
          side
            | all (> guardDistance) heights = Just 1
            | all (< negate guardDistance) heights = Just (-1)
            | otherwise = Nothing
          across = unit (cross n hingeAxis)
          fixedSides = [dot across (pointAt 0 v ^-^ hingeOrigin) | v <- ids fixed, not (onHinge v)]
          fixedOneSide = not (null fixedSides) && (all (> guardDistance) fixedSides || all (< negate guardDistance) fixedSides)
       in if stationary
            && rotating
            && not (null interior)
            && angle /= 0
            && abs angle <= pi
            && inPlane hingeOrigin
            && abs (dot n hingeAxis) <= endpointRoundoff
            && all (inPlane . pointAt t) (ids moving)
            && (restingBoundary fixed moving || (fixedOneSide && (sharedBoundaryOnly onHinge fixed moving || stackBoundaryOnly fixed moving)))
            then (fixed,moving,) <$> side
            else Nothing
    -- Preparation fixes vertices within 1e-12 of the axis. Such a vertex must
    -- also meet the much tighter contact allowance: otherwise a nearly hinged
    -- corner could stay on the wrong side while its interior lifts away.
    restingBoundary fixed moving =
      S.member (min fixed moving, max fixed moving) restingContacts
        && all (\v -> let distance = norm (cross hingeAxis (pointAt 0 v ^-^ hingeOrigin)) in distance > 1e-12 || distance <= endpointRoundoff) (ids moving)
    sharedBoundaryOnly onHinge fixed moving =
      let extent vs = let ds = map (\v -> dot hingeAxis (pointAt 0 v ^-^ hingeOrigin)) vs in (minimum ds, maximum ds)
          common = filter (`elem` ids fixed) (ids moving)
       in case (filter onHinge (ids fixed), filter onHinge (ids moving)) of
            ([], _) -> True
            (_, []) -> True
            (fs, ms) ->
              let (fa, fb) = extent fs
                  (ma, mb) = extent ms
               in case common of
                    [] -> max fa ma > min fb mb + guardDistance
                    _ -> let (ca, cb) = extent common in max fa ma >= ca && min fb mb <= cb
    -- A free stack edge is not a shared crease. Require a declared coplanar
    -- partner with the same motion, and REAL shared material on the other side.
    -- That shared segment must cover this pair's entire boundary contact.
    -- A fan triangle may touch the hinge only at its corner; a shared corner
    -- then supports only that point, never a longer unjoined edge.
    -- Supporting either side also handles a stationary stack and moving flap.
    -- Use the coplanarity allowance here, not the larger axis preparation
    -- tolerance: a nearly hinged free edge must not become a contact exemption.
    stackBoundaryOnly fixed moving =
      let onAxis v = norm (cross hingeAxis (pointAt 0 v ^-^ hingeOrigin)) <= endpointRoundoff
          extent vs = let ds = map (\v -> dot hingeAxis (pointAt 0 v ^-^ hingeOrigin)) vs in (minimum ds, maximum ds)
          partners i = [if a == i then b else a | (a, b) <- S.toList rigidContacts, a == i || b == i]
          supports lo hi a b = case filter (\v -> v `elem` ids b && onAxis v) (ids a) of
            common@(_ : _) -> let (ca, cb) = extent common in lo >= ca - endpointRoundoff && hi <= cb + endpointRoundoff
            _ -> False
       in case (filter onAxis (ids fixed), filter onAxis (ids moving)) of
            ([], _) -> False
            (_, []) -> False
            (fs, ms) ->
              let (fa, fb) = extent fs
                  (ma, mb) = extent ms
                  lo = max fa ma
                  hi = min fb mb
                  -- Every boundary corner recognized by preparation must
                  -- meet the tighter test, including corners beyond overlap.
                  tight i = all (\v -> norm (cross hingeAxis (pointAt 0 v ^-^ hingeOrigin)) > 1e-12 || onAxis v) (ids i)
               in lo <= hi + endpointRoundoff
                    && tight fixed
                    && tight moving
                    && (any (supports lo hi fixed) (partners moving) || any (\p -> supports lo hi p moving) (partners fixed))
    projected axis origin lo hi i = case IM.lookup i orbits of
      Just (Fixed p) -> let d = dot axis (p ^-^ origin) in (d, d)
      Just (Turning c u v) -> let d = dot axis (c ^-^ origin); (a, b) = rangeWithin (dot axis u) (dot axis v) (lo * angle) (hi * angle) in (d + a, d + b)
      Nothing -> (negate (1 / 0), 1 / 0)
    separated lo hi (i, j) = M.member (i, j) endpointPlanes || any along axes || hingeSide i j || hingeSide j i || stackHingeSide i j || stackHingeSide j i
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
        -- The same stationary plane argument, with the stack-supported
        -- boundary above instead of shared ids between these two triangles.
        stackHingeSide fixed moving =
          let axis = unit (normal (points 0 fixed))
              origin = pointAt 0 (minimum (ids fixed))
              onHinge v = norm (cross hingeAxis (pointAt 0 v ^-^ hingeOrigin)) <= endpointRoundoff
              fixedInterior = filter (not . onHinge) (ids fixed)
              movingInterior = filter (not . onHinge) (ids moving)
              stationary = all (\v -> case IM.lookup v orbits of Just (Fixed _) -> True; _ -> False) (ids fixed)
              oneSide ranges = not (null ranges) && (all ((> guardDistance) . fst) ranges || all ((< negate guardDistance) . snd) ranges)
              across = unit (cross axis hingeAxis)
              -- This distance is from the hinge, not the plane's arbitrary
              -- origin (which may itself be an off-hinge triangle corner).
              fixedSides = [let d = dot across (pointAt 0 v ^-^ hingeOrigin) in (d, d) | v <- fixedInterior]
           in stationary
                && stackBoundaryOnly fixed moving
                && abs (dot axis (hingeOrigin ^-^ origin)) <= endpointRoundoff
                && abs (dot axis hingeAxis) <= endpointRoundoff
                && oneSide fixedSides
                && oneSide (map (projected axis origin lo hi) movingInterior)
    inspect current (i, j) = do
      let vertices = IM.fromList (zip [0 ..] (samples current))
          panel index = Panel.Panel (tshow index) [position p | v <- ids index, Just p <- [IM.lookup v vertices]]
      first SweepGeometry (Panel.checkPanelContact (V3 0 0 1) [] [panel i, panel j])
    collisions current candidates = concat <$> mapM (\pair -> do report <- inspect current pair; pure [pair | not (Panel.contactPassed report)]) candidates
    endpoint t current = do
      reports <- mapM (\pair -> (,) pair <$> inspect current pair) pairs
      let contact pair = do
            (fixed, moving, side) <- M.lookup pair endpointPlanes
            -- A separating plane can also certify an OPEN endpoint. Only
            -- record contact when this endpoint actually lies in that plane.
            let n = unit (normal (points 0 fixed))
                origin = pointAt 0 (minimum (ids fixed))
            if all (\p -> abs (dot n (p ^-^ origin)) <= endpointRoundoff) (points t moving)
              then Just (EndpointContact t fixed moving side)
              else Nothing
          accepted = [(pair, c) | (pair, report) <- reports, null (Panel.crossingPanels report), not (null (Panel.unorderedContacts report)), Just c <- [contact pair]]
          retained pair report = S.member pair rigidContacts && null (Panel.crossingPanels report)
      pure ([pair | (pair, report) <- reports, not (Panel.contactPassed report), pair `notElem` map fst accepted, not (retained pair report)], map snd accepted)
    walk count depth lo hi candidates
      | count >= sweepBudget settings = pure (SweepCheck (SweepUnresolved lo hi candidates) count [])
      | otherwise = do
          let remaining = filter (not . separated lo hi) candidates
              midpoint = (lo + hi) / 2
              used = count + 1
          if null remaining
            then pure (SweepCheck SweepClear used [])
            else do
              middle <- sweepMeshAt sweep midpoint
              bad <- collisions middle remaining
              if not (null bad)
                then pure (SweepCheck (SweepCollision midpoint bad) used [])
                else
                  if depth == 0
                    then pure (SweepCheck (SweepUnresolved lo hi remaining) used [])
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
