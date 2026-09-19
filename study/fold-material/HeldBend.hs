-- | A prescribed arc followed by a straight section, reaching the original
-- inner and outer grips. Material coordinates locate the unfolded sheet;
-- see docs/glossary.md. Both panels coincide, with only the real crease shared.
-- This is a geometric reference, never a material-energy minimum or a route.
-- A tangent is the direction along the profile; curvature is how quickly
-- that direction turns per unit material length.
--
-- A circular arc alone cannot satisfy the grip position, tangent and available
-- paper length. Adding a straight tangent section supplies the extra freedom.
-- One scalar bisection constructs the circular reference. Sampling it shortens
-- chords; restoring each chord's material length moves the outer grip. A small
-- two-parameter fit therefore adjusts curvature and arc length per mesh. Its
-- endpoint Jacobian (the matrix of coordinate changes per parameter change)
-- comes from the curve, not the material/contact solver.
-- Those fitted references are deliberately not called the same smooth shape.
-- The smooth-transition control changes only the prescribed family, retaining
-- the circular reference and all material/hold/contact rules. It tests mesh
-- sensitivity; smooth curvature alone does not promise a smaller energy gap.
module HeldBend
  ( HeldCurve,
    curveCurvature,
    CurveTransition (..),
    curveTransition,
    makeCurveWith,
    commonCurveWith,
    commonCurveFit,
    heldProbeWith,
    curveCurvatureAt,
    curveEnergyBetween,
    curveArcLength,
    heldStart,
    freeLength,
    makeCurve,
    commonCurve,
    gripTarget,
    curvePoint,
    curveDifferential,
    polygonProfile,
    polygonEndpoint,
    curveEnergy,
    predictedPassive,
    HeldConstruction (..),
    FitStep (..),
    HeldProbe (..),
    heldProbe,
  )
where

import BandBoundary (BoundaryRule (..))
import ClosedCrease
import Control.Monad (forM, unless)
import CoupledCrease
import CreaseInequality (InequalityError (..))
import Data.IntMap.Strict qualified as IM
import Data.List (foldl')
import Data.Map.Strict qualified as M
import OuterStrip
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import UnequalCrease (UnequalControl (..))

-- | The old circular arc switches curvature abruptly. The cubic tangent
-- transition has zero curvature at both joins; its fixed shape is never tuned
-- against energy. Both families use mean curvature and bend length as parameters.
data CurveTransition = CircularArc | SmoothTransition
  deriving stock (Eq, Show)

data HeldCurve = HeldCurve {curveTransition :: !CurveTransition, curveCurvature :: !Double, curveArcLength :: !Double}
  deriving stock (Eq, Show)

heldStart, freeLength :: Double
heldStart = 1 / 8
freeLength = 3 / 8

-- | This family progresses in +x, so the existing directional contact audit
-- applies. Invalid parameters are refused before division or trigonometry.
makeCurve :: Double -> Double -> Either InequalityError HeldCurve
makeCurve = makeCurveWith CircularArc

makeCurveWith :: CurveTransition -> Double -> Double -> Either InequalityError HeldCurve
makeCurveWith transition k a
  | all (\x -> not (isNaN x || isInfinite x)) [k, a] && k > 0 && a > 0 && a < freeLength && k * a < pi / 2 = Right (HeldCurve transition k a)
  | otherwise = Left (InequalityError "held bend requires positive finite curvature and arc length, a remaining straight section, and a turn below 90 degrees")

gripTarget :: Either InequalityError V3
gripTarget = do
  f <- outerFixture Coarse OriginalTurns MatchedHolds
  case [position p | p <- samples (closedMesh (coupledReference f)), materialU p == 0.5, materialV p == 0] of
    [p] -> pure p
    _ -> Left (InequalityError "held bend lost the original outer grip")

-- | For final tangent angle t, solving the two endpoint equations gives a
-- radius r and straight length q. Bisect r*t+q = available material length.
-- This determines geometry only: no bending energy is consulted.
commonCurve :: Either InequalityError HeldCurve
commonCurve = do
  V3 targetX _ z <- gripTarget
  let x = targetX - heldStart
      phi = atan2 z x
      parts t = let d = 2 * sin (t / 2) ^ (2 :: Int); r = (x * sin t - z * cos t) / d; q = z * sin t / d - x in (r, q)
      total t = let (r, q) = parts t in r * t + q
      bisect 0 lo hi = (lo + hi) / 2
      bisect n lo hi = let mid = (lo + hi) / 2 in if total mid < freeLength then bisect (n - 1) mid hi else bisect (n - 1) lo mid
  unless (x > 0 && z > 0 && 2 * phi < pi / 2 && sqrt (x * x + z * z) < freeLength && total (2 * phi) > freeLength) $
    Left (InequalityError "original grips do not bracket this arc-and-straight reference")
  let t = bisect (64 :: Int) phi (2 * phi)
      (r, _) = parts t
  makeCurve (1 / r) (r * t)

-- | Retain the old closed-form construction verbatim. The smooth family
-- solves the same endpoint equations using its integrated tangent instead.
commonCurveWith :: CurveTransition -> Either InequalityError HeldCurve
commonCurveWith transition = fst <$> commonCurveFit transition

commonCurveFit :: CurveTransition -> Either InequalityError (HeldCurve, [FitStep])
commonCurveFit CircularArc = do c <- commonCurve; pure (c, [])
commonCurveFit SmoothTransition = do
  old <- commonCurve
  start <- makeCurveWith SmoothTransition (curveCurvature old) (curveArcLength old)
  target <- gripTarget
  fitEndpoint (`curveDifferential` 0.5) target start

curvePoint :: HeldCurve -> Double -> Double -> V3
curvePoint c distance y = let (V3 x _ z, _, _) = curveDifferential c distance in V3 x y z

-- | Position and derivatives with respect to curvature and arc length. The
-- tangent is continuous at both joins, including where a join cuts a strip.
curveDifferential :: HeldCurve -> Double -> (V3, V3, V3)
curveDifferential c distance
  | curveTransition c == SmoothTransition = smoothDifferential c distance
  | distance <= heldStart = (V3 distance 0 0, V3 0 0 0, V3 0 0 0)
  | otherwise =
      let t = min (distance - heldStart) a
          straight = max 0 (distance - heldStart - a)
          theta = k * t
          s = sin theta
          co = cos theta
          oneMinus = 2 * sin (theta / 2) ^ (2 :: Int)
          p = V3 (heldStart + s / k + straight * co) 0 (oneMinus / k + straight * s)
          dk = V3 ((k * t * co - s) / (k * k) - straight * t * s) 0 ((k * t * s - oneMinus) / (k * k) + straight * t * co)
          da = V3 (negate (straight * k * s)) 0 (straight * k * co)
       in (p, dk, da)
  where
    k = curveCurvature c
    a = curveArcLength c

-- | Let u run from zero to one through the bend. Its tangent angle is
-- k*A*(3*u^2 - 2*u^3), hence curvature is 6*k*u*(1-u). Integrating the unit
-- tangent preserves continuous material length. Derivatives include the
-- moving integration limit: omitting -u*tangent would fit the wrong endpoint.
smoothDifferential :: HeldCurve -> Double -> (V3, V3, V3)
smoothDifferential c distance
  | distance <= heldStart = (V3 distance 0 0, zero, zero)
  | otherwise =
      let u = min 1 ((distance - heldStart) / a)
          q = max 0 (distance - heldStart - a)
          angle = k * a
          turn t = t * t * (3 - 2 * t)
          tangent t = V3 (cos t) 0 (sin t)
          normal t = V3 (negate (sin t)) 0 (cos t)
          integral = integrate u (tangent . (angle *) . turn)
          derivative = integrate u (\t -> turn t *^ normal (angle * turn t))
          p = V3 heldStart 0 0 ^+^ a *^ integral ^+^ q *^ tangent angle
          dk = (a * a) *^ derivative ^+^ (q * a) *^ normal angle
          da = integral ^+^ (a * k) *^ derivative ^-^ u *^ tangent (angle * turn u) ^+^ (q * k) *^ normal angle
       in (p, dk, da)
  where
    k = curveCurvature c
    a = curveArcLength c
    zero = V3 0 0 0

-- Eight-point Gauss-Legendre integration on four equal subintervals. These
-- weighted samples integrate degree-15 polynomials exactly in exact arithmetic.
-- Independent Simpson sums check our trigonometric integrals; finite
-- differences check their parameter derivatives.
-- Integration resolution is fixed independently of the paper mesh.
integrate :: Double -> (Double -> V3) -> V3
integrate end f =
  foldl'
    (^+^)
    (V3 0 0 0)
    [ (weight * half) *^ f (mid + sign * half * node)
      | part <- [0 :: Int .. 3],
        let half = end / 8; mid = (fromIntegral part + 0.5) * end / 4,
        (node, weight) <- [(0.1834346424956498, 0.362683783378362), (0.525532409916329, 0.3137066458778873), (0.7966664774136267, 0.2223810344533745), (0.9602898564975363, 0.1012285362903763)],
        sign <- [-1, 1]
    ]

curveCurvatureAt :: HeldCurve -> Double -> Double
curveCurvatureAt c distance
  | distance <= heldStart || distance >= heldStart + curveArcLength c = 0
  | curveTransition c == CircularArc = curveCurvature c
  | otherwise = 6 * curveCurvature c * u * (1 - u)
  where
    u = (distance - heldStart) / curveArcLength c

-- | Continuous comparison per unit-width panel. For the smooth family,
-- integrate (6*k*u*(1-u))^2 analytically over each material interval.
curveEnergyBetween :: HeldCurve -> Double -> Double -> Double
curveEnergyBetween c left right
  | right <= left = 0
  | curveTransition c == CircularArc = 0.1 * k ^ (2 :: Int) * max 0 (min right (heldStart + a) - max left heldStart)
  | otherwise = 0.1 * k * k * a * (primitive right - primitive left)
  where
    k = curveCurvature c
    a = curveArcLength c
    primitive s = let u = max 0 (min 1 ((s - heldStart) / a)) in u * u * u * (12 + u * (-18 + 7.2 * u))

-- Each row is (material length, chord direction, d(direction)/dk, d/dA).
segments :: OuterMesh -> HeldCurve -> [(Double, Double, Double, Double)]
segments mesh c =
  [ let (pa, ka, aa) = curveDifferential c a
        (pb, kb, ab) = curveDifferential c b
        V3 x _ z = pb ^-^ pa
        derivative (V3 dx _ dz) = (x * dz - z * dx) / (x * x + z * z)
     in (b - a, atan2 z x, derivative (kb ^-^ ka), derivative (ab ^-^ aa))
    | (a, b) <- zip columns (drop 1 columns)
  ]
  where
    columns = map fromRational (outerColumns mesh)

polygonProfile :: OuterMesh -> HeldCurve -> [V3]
polygonProfile mesh c = scanl (^+^) (V3 0 0 0) [V3 (h * cos angle) 0 (h * sin angle) | (h, angle, _, _) <- segments mesh c]

polygonEndpoint :: OuterMesh -> HeldCurve -> (V3, V3, V3)
polygonEndpoint mesh c = foldl' add (V3 0 0 0, V3 0 0 0, V3 0 0 0) (segments mesh c)
  where
    add (p, k, a) (h, angle, dk, da) =
      let direction = V3 (cos angle) 0 (sin angle)
          turn = V3 (negate (h * sin angle)) 0 (h * cos angle)
       in (p ^+^ h *^ direction, k ^+^ dk *^ turn, a ^+^ da *^ turn)

curveEnergy :: HeldCurve -> Double
curveEnergy c
  | curveTransition c == CircularArc = 0.1 * curveCurvature c ^ (2 :: Int) * curveArcLength c
  | otherwise = 0.12 * curveCurvature c ^ (2 :: Int) * curveArcLength c

-- | Independent one-dimensional angular cost, for either panel. End joins
-- need not be mesh columns: use actual chord directions, not midpoint turns.
predictedPassive :: OuterMesh -> HeldCurve -> Double
predictedPassive mesh c = sum [0.1 * (q - p) ^ (2 :: Int) / ((a + b) / 2) | ((a, p, _, _), (b, q, _, _)) <- zip rows (drop 1 rows)]
  where
    rows = segments mesh c

data HeldConstruction = CurveSamples | FullLengthReference | FullLengthHeld
  deriving stock (Eq, Show, Enum, Bounded)

data FitStep = FitStep {fitIteration :: !Int, fitCurve :: !HeldCurve, fitResidual :: !Double}
  deriving stock (Eq, Show)

data HeldProbe = HeldProbe
  { heldPaper :: !ClosedCrease,
    heldOriginal :: !CoupledFixture,
    heldCurve :: !HeldCurve,
    heldFitSteps :: ![FitStep],
    heldRawEndpoint :: !V3,
    heldPinAdjustment :: !Double
  }
  deriving stock (Show)

-- | Solve only two geometric endpoint equations, with a bounded, damped
-- Newton step: solve linearized endpoint equations, shortening the step until
-- the endpoint error decreases. Curve parameters may change; springs never do.
fitCurveToGrips :: OuterMesh -> V3 -> HeldCurve -> Either InequalityError (HeldCurve, [FitStep])
fitCurveToGrips mesh = fitEndpoint (polygonEndpoint mesh)

fitEndpoint :: (HeldCurve -> (V3, V3, V3)) -> V3 -> HeldCurve -> Either InequalityError (HeldCurve, [FitStep])
fitEndpoint endpoint target = go 0 []
  where
    go iteration history c = do
      let (p, V3 kx _ kz, V3 ax _ az) = endpoint c
          residual = target ^-^ p
          distance = norm residual
          history' = history ++ [FitStep iteration c distance]
          determinant = kx * az - ax * kz
          V3 x _ z = residual
      if distance <= 1e-14
        then pure (c, history')
        else do
          unless (iteration < 16 && abs determinant > 1e-12) (Left (InequalityError "held-bend geometric fit exhausted its budget or has a singular endpoint Jacobian"))
          let dk = (x * az - z * ax) / determinant
              da = (kx * z - kz * x) / determinant
              trial [] = Left (InequalityError "held-bend geometric fit cannot reduce the grip residual")
              trial (scale : rest) = case makeCurveWith (curveTransition c) (curveCurvature c + scale * dk) (curveArcLength c + scale * da) of
                Right candidate | let (q, _, _) = endpoint candidate, norm (target ^-^ q) < distance -> pure candidate
                _ -> trial rest
          next <- trial [0.5 ^ i | i <- [0 :: Int .. 12]]
          go (iteration + 1) history' next

heldProbe :: OuterMesh -> HeldConstruction -> Either InequalityError HeldProbe
heldProbe = heldProbeWith CircularArc

heldProbeWith :: CurveTransition -> OuterMesh -> HeldConstruction -> Either InequalityError HeldProbe
heldProbeWith transition meshChoice construction = do
  original <- outerFixture meshChoice OriginalTurns MatchedHolds
  reference <- commonCurveWith transition
  target <- gripTarget
  (c, steps) <- if construction == FullLengthHeld then fitCurveToGrips meshChoice target reference else pure (reference, [])
  let base = coupledReference original
      mesh = closedMesh base
      columns = map fromRational (outerColumns meshChoice)
      polygon = M.fromList (zip columns (polygonProfile meshChoice c))
      place p = case construction of
        CurveSamples -> pure (curvePoint c (abs (materialU p)) (materialV p))
        _ -> case M.lookup (abs (materialU p)) polygon of
          Just (V3 x _ z) -> pure (V3 x (materialV p) z)
          Nothing -> Left (InequalityError "held bend lost a material column")
  raw <- forM (samples mesh) $ \p -> do q <- place p; pure p {position = q}
  -- Copy authored grips only after a reference reaches them to numerical
  -- precision. This removes roundoff, never hides a failed geometric fit;
  -- every final material edge is measured after the copy.
  let adjustments = [norm (position p ^-^ q) | (i, p) <- zip [0 ..] raw, Just q <- [IM.lookup i (coupledPins original)]]
      adjustment = if construction == FullLengthReference then 0 else maximum (0 : adjustments)
      placePin i p = if construction == FullLengthReference then p else maybe p (\q -> p {position = q}) (IM.lookup i (coupledPins original))
      points = zipWith placePin [0 ..] raw
      profile = [(toRational x, toRational z) | p <- points, materialU p >= 0, materialV p == -0.5, let V3 x _ z = position p]
      endpoint = case construction of CurveSamples -> curvePoint c 0.5 0; _ -> let (p, _, _) = polygonEndpoint meshChoice c in p
  unless (adjustment <= 1e-14) (Left (InequalityError "held bend refuses to snap a missed grip onto its target"))
  pure (HeldProbe base {closedMesh = mesh {samples = points}, lowerProfile = profile, upperProfile = profile} original c steps endpoint adjustment)
