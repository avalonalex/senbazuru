-- | Test the existing contact solver against one fixed bending panel.
-- The lower half of ClosedCrease stays at its known shape. The upper outer
-- strip is held too; the remaining upper vertices can move in all three
-- coordinates. The crease shares the lower panel's held vertices, but its
-- angle is a spring preference, not an extra positional hold.
-- See docs/glossary.md for panels, material coordinates and layer order.
--
-- A solved upper panel need not remain an extruded profile. 'auditLowerGap'
-- therefore clips each of its triangles against the fixed lower profile's
-- vertical strips, including the finite width in y. Within each clipped
-- piece the upper-minus-lower height is linear, so its extrema occur at the
-- corners. Rational arithmetic measures the stored Double coordinates
-- exactly, independently of contact-force derivatives and distance snapping.
-- This checks order against the LOWER panel, not upper self-contact or a
-- physical path. The ordinary whole-mesh checker remains a separate gate.
module CreaseCorrection
  ( CorrectionControl (..),
    CreaseCorrection (..),
    CorrectionError (..),
    GapAudit (..),
    creaseCorrection,
    solveCorrection,
    auditLowerGap,
    correctionSurface,
  )
where

import ClosedCrease
import Control.Monad (forM, forM_, unless)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact

data CorrectionControl = ReferenceStart | PenetratingGuess | WithoutContact | TinyPenetration | ConflictingHold
  deriving stock (Eq, Show, Enum, Bounded)

data CreaseCorrection = CreaseCorrection
  { correctionReference :: !ClosedCrease,
    correctionSeed :: !MaterialMesh,
    correctionPins :: !(IM.IntMap V3),
    correctionForces :: !Bool
  }
  deriving stock (Show)

newtype CorrectionError = CorrectionError Text deriving stock (Eq, Show)

instance Explain CorrectionError where explain (CorrectionError message) = message

-- | Gap polygons are projections onto (folded x, upper-minus-lower height).
-- Keeping every clipped piece covers all upper triangles, even when rows
-- warp differently along y. A negative minimum records penetration without
-- rounding it into a numerical pass. No physical thickness is introduced.
data GapAudit = GapAudit
  { gapPolygons :: ![[(Rational, Rational)]],
    minimumGap :: !Rational,
    maximumGap :: !Rational
  }
  deriving stock (Eq, Show)

creaseCorrection :: Int -> CorrectionControl -> Either CorrectionError CreaseCorrection
creaseCorrection count control = do
  reference <- first (CorrectionError . explain) (closedCrease count BentTouching)
  let mesh = closedMesh reference
      held p = materialU p >= 0 || abs (materialU p) >= 0.375
      conflict p = control == ConflictingHold && materialU p == -0.25
      amount = case control of
        ReferenceStart -> 0
        TinyPenetration -> 2e-8
        _ -> 0.002
      moved p
        | held p = p
        | otherwise = p {position = position p ^-^ V3 0 0 (amount * sin (pi * abs (materialU p) / 0.5))}
      seed = mesh {samples = map moved (samples mesh)}
      -- A conflicting hold is already installed in the seed. This keeps
      -- before/after reports honest about which positions the solver receives.
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] (samples seed), held p || conflict p]
  pure (CreaseCorrection reference seed pins (control /= WithoutContact))

solveCorrection :: Settings -> CreaseCorrection -> Either CorrectionError (Relaxation, Maybe TrialDiagnostics)
solveCorrection settings fixture = do
  checkMaterial fixture seed
  if correctionForces fixture
    then do
      contact <- first (CorrectionError . explain) (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners reference) seed)
      (result, audit) <- first (CorrectionError . explain) (diagnosePinnedContact settings (correctionPins fixture) (closedHinges reference) contact seed)
      pure (result, Just audit)
    else do
      result <- first (CorrectionError . explain) (relaxPinnedHinges settings (correctionPins fixture) (closedHinges reference) seed)
      pure (result, Nothing)
  where
    reference = correctionReference fixture
    seed = correctionSeed fixture

checkMaterial :: CreaseCorrection -> MaterialMesh -> Either CorrectionError ()
checkMaterial fixture mesh = do
  let reference = closedMesh (correctionReference fixture)
  unless (triangles mesh == triangles reference && map sampleMaterial (samples mesh) == map sampleMaterial (samples reference)) (Left (CorrectionError "crease correction must retain its material and triangle identities"))
  unless (all (\p -> let V3 x y z = position p in all (\v -> not (isNaN v || isInfinite v)) [x, y, z]) (samples mesh)) (Left (CorrectionError "crease correction needs finite positions"))
  unless (and [position p == position q | (p, q) <- zip (samples mesh) (samples reference), materialU q >= 0]) (Left (CorrectionError "the independent gap reference requires the whole lower panel to stay fixed"))

auditLowerGap :: CreaseCorrection -> MaterialMesh -> Either CorrectionError GapAudit
auditLowerGap fixture mesh = do
  checkMaterial fixture mesh
  let vertices = IM.fromList (zip [0 ..] (map (rational . position) (samples mesh)))
      vertex i = maybe (Left (CorrectionError "gap reference lost a triangle vertex")) Right (IM.lookup i vertices)
      reference = correctionReference fixture
      -- These are the STORED reference coordinates, not the ideal fractions
      -- from ClosedCrease. Thus exact touching in the input remains zero.
      profile = [(toRational x, toRational z) | p <- samples (closedMesh reference), materialU p >= 0, materialV p == -0.5, let V3 x _ z = position p]
      spans = zip profile (drop 1 profile)
  unless (not (null spans) && all (\((x, _), (y, _)) -> x < y) spans) (Left (CorrectionError "the lower reference must progress in positive x"))
  upper <- forM [t | (t, owner) <- zip (triangles mesh) (closedOwners reference), owner == FaceId 1] $ \(a, b, c) -> mapM vertex [a, b, c]
  let pieces =
        [ map (gap spanEnds) clipped
          | triangle <- upper,
            spanEnds@((a, _), (b, _)) <- spans,
            let clipped = clipToStrip a b triangle,
            not (null clipped)
        ]
      heights = [z | polygon <- pieces, (_, z) <- polygon]
  case heights of
    [] -> Left (CorrectionError "the upper panel has no overlap with the lower reference")
    _ -> pure (GapAudit pieces (minimum heights) (maximum heights))
  where
    rational (V3 x y z) = (toRational x, toRational y, toRational z)
    gap ((a, u), (b, v)) (x, _, z) = (x, z - u - (x - a) * (v - u) / (b - a))

type Point = (Rational, Rational, Rational)

-- Keep the overlap with one full-width strip of the held lower panel.
clipToStrip :: Rational -> Rational -> [Point] -> [Point]
clipToStrip a b triangle =
  let afterLeft = clip (\(x, _, _) -> x - a) triangle
      afterRight = clip (\(x, _, _) -> b - x) afterLeft
      afterBottom = clip (\(_, y, _) -> y + 1 / 2) afterRight
   in clip (\(_, y, _) -> 1 / 2 - y) afterBottom

-- Cut by a vertical half-space; the distance is linear, so interpolation
-- gives an exact boundary point. Equality includes legal touching points.
clip :: (Point -> Rational) -> [Point] -> [Point]
clip distance points = concatMap edge (zip points (drop 1 points ++ take 1 points))
  where
    edge (p, q)
      | dp >= 0 && dq >= 0 = [q]
      | dp < 0 && dq < 0 = []
      | otherwise = let hit = interpolate (dp / (dp - dq)) p q in if dq >= 0 then [hit, q] else [hit]
      where
        dp = distance p; dq = distance q
    interpolate t (x, y, z) (a, b, c) = (x + t * (a - x), y + t * (b - y), z + t * (c - z))

-- | Export only after checking the material and the orientation on which
-- ClosedCrease's FOLD order signs depend. This is still a diagnostic export;
-- it does not turn a small negative gap into accepted paper.
correctionSurface :: CreaseCorrection -> MaterialMesh -> Either CorrectionError (Surface V2)
correctionSurface fixture mesh = do
  checkMaterial fixture mesh
  let reference = correctionReference fixture
      vertices = IM.fromList (zip [0 ..] (map position (samples mesh)))
      vertex i = maybe (Left (CorrectionError "crease export lost a triangle vertex")) Right (IM.lookup i vertices)
  forM_ [(t, owner) | (t, owner) <- zip (triangles mesh) (closedOwners reference)] $ \((a, b, c), owner) -> do
    p <- vertex a
    q <- vertex b
    r <- vertex c
    let V3 _ _ z = cross (q ^-^ p) (r ^-^ p)
    unless (if owner == FaceId 0 then z > 0 else z < 0) (Left (CorrectionError "crease export requires the lower and upper panel to retain their facing directions"))
  first (CorrectionError . explain) (closedSurface reference {closedMesh = mesh})
