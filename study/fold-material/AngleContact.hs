-- | Choose crease angles using loop closure and inherited layer order together.
-- A provisional walk can leave neighboring panels unjoined. Each triangle gets
-- separate temporary corners so contact does not silently weld that error away.
-- Original material ids still decide which pairs may share a zero gap. These
-- temporary placements are never a shared paper mesh or a folding animation.
--
-- One extra scalar bounds every loop disagreement and contact deficit. The
-- constrained quadratic lowers this common bound, not a weighted material
-- energy. Including it makes the linear problem feasible even at an intersecting
-- start. Original-row checks and remeasured trial geometry can still refuse the
-- direction. Only production folding and independent contact checks can accept
-- paper. See docs/notes/body-angle-contact.md for the declared bounded study.
module AngleContact
  ( AngleContactInput (..),
    AngleMeasurement (..),
    AngleConstraint (..),
    ContactAngleTrial (..),
    ContactAngleAttempt (..),
    ContactAngleRun (..),
    measureAngles,
    angleContactProblem,
    contactAngleSearch,
    provisionalTriangles,
  )
where

import ContactQuadratic qualified as Q
import Control.Monad (forM, unless)
import CreaseSeed
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FoldContact (ContactRow (..))
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C

data AngleContactInput = AngleContactInput
  { contactPattern :: Frame,
    contactMaterial :: MaterialMesh,
    contactOwners :: [FaceId],
    contactOrders :: [(FaceId, FaceId)],
    contactAlignment :: Rigid
  }
  deriving stock (Show)

data AngleMeasurement = AngleMeasurement
  { measuredDegrees :: [Double],
    measuredClosure :: [Double],
    measuredGaps :: [((Int, Int), Double, Double)],
    measuredWorst :: Double
  }
  deriving stock (Eq, Show)

data AngleConstraint = AngleConstraint
  { constraintName :: Text,
    constraintGradient :: IM.IntMap V3,
    constraintOffset :: Double
  }
  deriving stock (Eq, Show)

data ContactAngleTrial = ContactAngleTrial Double [Double] (Maybe AngleMeasurement) (Maybe Text)
  deriving stock (Show)

data ContactAngleAttempt = ContactAngleAttempt
  { attemptConstraints :: [AngleConstraint],
    attemptDirection :: Maybe (IM.IntMap V3),
    attemptReport :: Maybe Q.QuadraticReport,
    attemptDetails :: Maybe Q.QuadraticDetails,
    attemptFailure :: Maybe Text,
    attemptTrials :: [ContactAngleTrial]
  }
  deriving stock (Show)

data ContactAngleRun = ContactAngleRun
  { contactAngleHistory :: [AngleMeasurement],
    contactAngleAttempts :: [ContactAngleAttempt],
    contactAngleStop :: Text
  }
  deriving stock (Show)

-- | Separate corners are numerical work space only. Their material coordinates
-- remain real, but their temporary vertex ids do not describe paper adjacency.
provisionalTriangles :: AngleContactInput -> [Double] -> Either CreaseSeedError MaterialMesh
provisionalTriangles input angles = do
  placements <- creasePlacements (contactPattern input) angles
  let mesh = contactMaterial input
      points = IM.fromList (zip [0 :: Int ..] (samples mesh))
  unless (length (contactOwners input) == length (triangles mesh)) (bad "one panel owner is needed per triangle")
  corners <- forM (zip (contactOwners input) (triangles mesh)) $ \(FaceId owner, (a, b, c)) -> do
    transform <- lookupValue "missing provisional panel" owner placements
    forM [a, b, c] $ \i -> do
      sample <- lookupValue "missing material corner" i points
      let V2 u v = sampleMaterial sample
      pure sample {position = applyRigid (contactAlignment input `after` transform) (V3 u v 0)}
  pure (Mesh (concat corners) [(3 * i, 3 * i + 1, 3 * i + 2) | i <- [0 .. length corners - 1]])

witnesses :: AngleContactInput -> MaterialMesh -> Either CreaseSeedError [C.ContactWitness]
witnesses input mesh = do
  model <- adapt (C.prepareContact 0 (V3 0 0 1) (contactOrders input) (contactOwners input) mesh)
  adapt (C.contactWitnesses model mesh)

targetFor :: AngleContactInput -> (Int, Int) -> Either CreaseSeedError Double
targetFor input (a, b) = do
  let topology = IM.fromList (zip [0 :: Int ..] (triangles (contactMaterial input)))
      corners i = do (x, y, z) <- lookupValue "missing material triangle" i topology; pure [x, y, z]
  av <- corners a
  bv <- corners b
  pure (if all (`notElem` bv) av then 1e-6 else 0)

measureAngles :: AngleContactInput -> [Double] -> Either CreaseSeedError AngleMeasurement
measureAngles input degrees = do
  closure <- creaseResiduals (contactPattern input) degrees
  mesh <- provisionalTriangles input degrees
  ws <- witnesses input mesh
  gaps <- forM ws $ \w -> do
    target <- targetFor input (C.witnessTriangles w)
    pure (C.witnessTriangles w, contactGap (C.witnessRow w), target)
  let worst = maximum (0 : map abs closure ++ [target - gap | (_, gap, target) <- gaps])
  unless (all finite (worst : closure ++ [g | (_, g, _) <- gaps])) (bad "nonfinite crease/contact measurement")
  pure (AngleMeasurement degrees closure gaps worst)

-- The x entry of each V3 block is an angle increment in degrees. The extra
-- block's x is the scaled common bound; y/z are unused and damped to zero.
-- No angle id or auxiliary id is a material vertex.
angleContactProblem :: AngleContactInput -> [Double] -> Either CreaseSeedError ([Int], Int, Double, [AngleConstraint])
angleContactProblem input degrees = do
  before <- measureAngles input degrees
  mesh <- provisionalTriangles input degrees
  ws <- witnesses input mesh
  let physical = [(i, if a == Mountain then -1 else 1) | (i, a) <- zip [0 :: Int ..] (edgesAssignment (contactPattern input)), a `elem` [Mountain, Valley]]
  anchor <- case physical of (i, _) : _ -> pure i; _ -> bad "contact-angle search needs a physical crease"
  let free = [i | (i, _) <- physical, i /= anchor]
      values = IM.fromList (zip [0 :: Int ..] degrees)
      auxiliary = length degrees
      scalar = IM.singleton auxiliary (V3 1 0 0)
      common = measuredWorst before / residualScale
      perturb i amount = [x + (if j == i then amount else 0) | (j, x) <- zip [0 :: Int ..] degrees]
      h = 1e-6 * 180 / pi
  columns <- forM free $ \i -> do
    plus <- creaseResiduals (contactPattern input) (perturb i h)
    minus <- creaseResiduals (contactPattern input) (perturb i (-h))
    plusMesh <- provisionalTriangles input (perturb i h)
    minusMesh <- provisionalTriangles input (perturb i (-h))
    let derivatives = IM.fromList (zip [0 :: Int ..] (zipWith (\p q -> (1 / (2 * h)) *^ (position p ^-^ position q)) (samples plusMesh) (samples minusMesh)))
        gaps = [sum [dot g (IM.findWithDefault (V3 0 0 0) v derivatives) | (v, g) <- contactGradient (C.witnessRow w)] | w <- ws]
    pure (i, zipWith (\a b -> (a - b) / (2 * h)) plus minus, gaps)
  let gradient valuesAt k = IM.fromList [(i, V3 (value / residualScale) 0 0) | (i, rs, gs) <- columns, (j, value) <- zip [0 :: Int ..] (valuesAt rs gs), j == k]
      bounds name g gap = AngleConstraint name (IM.unionWith (^+^) g scalar) (common + gap / residualScale)
      loopRows = [bounds ("closure " <> tshow k <> " " <> tshow sign) (IM.map (sign *^) (gradient const k)) (sign * r) | (k, r) <- zip [0 :: Int ..] (measuredClosure before), sign <- [-1, 1]]
  contactRows <- forM (zip [0 :: Int ..] ws) $ \(k, w) -> do
    target <- targetFor input (C.witnessTriangles w)
    pure (bounds ("contact " <> tshow (C.witnessTriangles w) <> " corner " <> tshow k) (gradient (\_ gaps -> gaps) k) (contactGap (C.witnessRow w) - target))
  boxes <- fmap concat $ forM [(i, s) | (i, s) <- physical, i /= anchor] $ \(i, s) -> do
    angle <- lookupValue "missing physical angle" i values
    let unit = IM.singleton i (V3 s 0 0)
    pure [AngleConstraint ("angle lower " <> tshow i) unit (s * angle - 150), AngleConstraint ("angle upper " <> tshow i) (IM.map ((-1) *^) unit) (179.99 - s * angle)]
  let trust = [AngleConstraint ("step " <> tshow i <> " " <> tshow sign) (IM.singleton i (V3 sign 0 0)) 5 | i <- free, sign <- [-1, 1]]
      rows = loopRows ++ contactRows ++ boxes ++ trust ++ [AngleConstraint "bound nonnegative" scalar common, AngleConstraint "bound nonincreasing" (IM.map ((-1) *^) scalar) 0]
  unless (all (\r -> finite (constraintOffset r) && constraintOffset r >= 0 && all finiteV (constraintGradient r)) rows) (bad "contact-angle linear start violates its bounds")
  pure (free ++ [auxiliary], auxiliary, common, rows)

contactAngleSearch :: Int -> AngleContactInput -> [Double] -> Either CreaseSeedError ContactAngleRun
contactAngleSearch budget input start = do
  unless (budget >= 0 && budget <= 40) (bad "contact-angle budget must be between zero and forty")
  let assignments = edgesAssignment (contactPattern input)
      physical = [(i, if a == Mountain then -1 else 1) | (i, a) <- zip [0 :: Int ..] assignments, a `elem` [Mountain, Valley]]
  (anchor, sign) <- case physical of x : _ -> pure x; _ -> bad "missing contact-angle anchor"
  unless (length assignments == length start && all finite start && and [if a `elem` [Mountain, Valley] then let s = if a == Mountain then -1 else 1 in s * x >= 150 && s * x <= 179.99 else x == 0 | (a, x) <- zip assignments start] && and [abs (x - sign * 175) < 1e-10 | (i, x) <- zip [0 :: Int ..] start, i == anchor]) (bad "contact-angle seed must preserve signed bounds, flat connections and the 175-degree anchor")
  firstMeasurement <- measureAngles input start
  go 0 [firstMeasurement] [] firstMeasurement
  where
    finish history attempts = ContactAngleRun (reverse history) (reverse attempts)
    go count history attempts current
      | maximum (0 : map abs (measuredClosure current)) <= 1e-10 && maximum (0 : [t - g | (_, g, t) <- measuredGaps current]) <= 1e-12 = pure (finish history attempts "construction-targets")
      | count >= budget = pure (finish history attempts "correction-budget")
      | otherwise = do
          let degrees = measuredDegrees current
          (ids, aux, common, rows) <- angleContactProblem input degrees
          let solve = Q.constrainedStepDetailed Q.OriginalWorkingSet 200 1e-8 ids [(IM.singleton aux (V3 1 0 0), common)] [(constraintGradient c, constraintOffset c) | c <- rows]
          case solve of
            Left err -> pure (finish history (ContactAngleAttempt rows Nothing Nothing Nothing (Just (explain err)) [] : attempts) "linear-failure")
            Right (delta, report, details) -> do
              let attempt = ContactAngleAttempt rows (Just delta) (Just report) (Just details)
                  candidate fraction = [x + fraction * dx | (i, x) <- zip [0 :: Int ..] degrees, let V3 dx _ _ = IM.findWithDefault (V3 0 0 0) i delta]
                  search tried [] = pure (reverse tried, Nothing)
                  search tried (fraction : rest) = do
                    let angles = candidate fraction
                        assignments = edgesAssignment (contactPattern input)
                        valid = and [if a `elem` [Mountain, Valley] then let s = if a == Mountain then -1 else 1 in s * x >= 150 && s * x <= 179.99 else x == 0 | (a, x) <- zip assignments angles]
                        measured = if valid then measureAngles input angles else bad "angle bound"
                        failure = case measured of Left err -> Just (explain err); Right m -> if measuredWorst m < measuredWorst current then Nothing else Just "worst construction residual did not decrease"
                        trial = ContactAngleTrial fraction angles (either (const Nothing) Just measured) failure
                    case (failure, measured) of
                      (Nothing, Right m) -> pure (reverse (trial : tried), Just m)
                      _ -> search (trial : tried) rest
              if not (Q.quadraticConverged report) || not (all finiteV delta)
                then pure (finish history (attempt (Just "original-row verification failed") [] : attempts) "linear-failure")
                else do
                  (trials, next) <- search [] [2 ** negate (fromIntegral i) | i <- [0 :: Int .. 12]]
                  case next of
                    Nothing -> pure (finish history (attempt Nothing trials : attempts) "line-search-budget")
                    Just m -> go (count + 1) (m : history) (attempt Nothing trials : attempts) m

residualScale :: Double
residualScale = 0.01

lookupValue :: Text -> Int -> IM.IntMap a -> Either CreaseSeedError a
lookupValue label i = maybe (bad label) Right . IM.lookup i

bad :: Text -> Either CreaseSeedError a
bad = Left . CreaseSeedError

adapt :: (Explain e) => Either e a -> Either CreaseSeedError a
adapt = first (CreaseSeedError . explain)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

finiteV :: V3 -> Bool
finiteV (V3 x y z) = all finite [x, y, z]
