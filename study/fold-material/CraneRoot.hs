-- | Separate the holds from the material preference at a crane wing's root.
-- A root is the line where the wing meets the body. The earlier experiment
-- fixes a whole strip there at 30 degrees, so changing a crease spring cannot
-- change that strip's direction. Here the tip grip stays identical while the
-- root strip and then its four neighbouring body panels can be released.
-- See docs/glossary.md for material coordinates, panels and rest angles.
--
-- A spring's rest angle is a preference, not an exact hold. The four authored
-- wing-root edges therefore have measured achieved angles, separate from the
-- original mountain/valley creases which this bounded study keeps folded.
-- Making a spring weaker need not make a smoother surface: rotation can become
-- cheaper at that one line than in the surrounding panel. No rendering change
-- participates in these comparisons, and no numerical iterate is a motion.
module CraneRoot
  ( RootControl (..),
    CraneRoot (..),
    craneRoot,
    rootAngles,
    originalCreaseError,
    rootBodyMovement,
    rootProfile,
    rootAccepted,
  )
where

import Control.Monad (unless)
import CraneSpread
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Set qualified as S
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Crease (..), Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface

data RootControl = HeldRoot | ReleasedRoot | WeakerRoot | FlatRoot | FreeBody
  deriving stock (Eq, Show)

data CraneRoot = CraneRoot
  { rootSpread :: !CraneSpread,
    rootEdges :: !(S.Set EdgeId),
    rootNeighbours :: !(S.Set FaceId)
  }
  deriving stock (Show)

-- | Every comparison refines the same eight source panels. Four are the
-- wing; four lie directly across its root edges. All vertices incident to
-- any OTHER panel remain held, even if also used by a released panel. Thus
-- the patch's distant boundary stays attached to the unchanged crane.
craneRoot :: Frame -> Int -> RootControl -> Either SpreadError CraneRoot
craneRoot source level control = do
  fixture <- craneSpreadWith WingAndRootNeighbours source level 20
  features <- first (SpreadError . explain) (surfaceFeatures (spreadSource fixture))
  let roots = [(creaseId edge, owners) | (edge, owners) <- features, creaseAssignment edge == Unassigned]
      edges = S.fromList (map fst roots)
      wing = spreadMoving fixture
      nearby = S.fromList (concatMap snd roots) S.\\ wing
      allowed = S.union wing nearby
      mesh = spreadMesh fixture
      vertices (a, b, c) = [a, b, c]
      distant = S.fromList [v | (tri, owner) <- zip (triangles mesh) (refinedPanels (spreadRefined fixture)), S.notMember owner allowed, v <- vertices tri]
      keep i = S.member i (spreadGrip fixture) || S.member i (if control == FreeBody then distant else spreadBody fixture)
      pins = if control == HeldRoot then spreadPins fixture else IM.filterWithKey (\i _ -> keep i) (spreadPins fixture)
      change hinge = case hingeRole hinge of
        SurfaceCrease eid | S.member eid edges -> case control of
          WeakerRoot -> hinge {hingeStiffness = 0.1 * hingeStiffness hinge}
          FlatRoot -> hinge {hingeRest = 0}
          FreeBody -> hinge {hingeRest = 0}
          _ -> hinge
        _ -> hinge
  unless (S.size edges == 4 && S.size nearby == 4) (Left (SpreadError "expected four wing-root edges and four neighbouring body panels"))
  pure (CraneRoot fixture {spreadPins = pins, spreadHinges = map change (spreadHinges fixture)} edges nearby)

-- | Signed angles in radians for every refined root segment, with source ids.
-- The two touching layers have opposite material normals, so their signs
-- differ even when their geometric turns agree. Keep those signs in the data.
rootAngles :: CraneRoot -> MaterialMesh -> Either SpreadError [(EdgeId, Double)]
rootAngles study mesh = mapM measure [(eid, h) | h <- spreadHinges (rootSpread study), SurfaceCrease eid <- [hingeRole h], S.member eid (rootEdges study)]
  where
    points = IM.fromList (zip [0 ..] (samples mesh))
    measure (eid, h) = do
      (angle, _) <- first (SpreadError . explain) (hingeAngle h points)
      pure (eid, angle)

originalCreaseError :: CraneRoot -> MaterialMesh -> Either SpreadError Double
originalCreaseError study = spreadAngleError fixture {spreadHinges = filter original (spreadHinges fixture)}
  where
    fixture = rootSpread study
    original hinge = case hingeRole hinge of
      SurfaceCrease eid -> S.notMember eid (rootEdges study)
      _ -> False

rootBodyMovement :: CraneRoot -> MaterialMesh -> Double
rootBodyMovement study mesh = maximum (0 : [norm (position p ^-^ position q) | (i, (p, q)) <- zip [0 ..] (zip (samples mesh) (samples original)), S.member i (spreadBody fixture)])
  where
    fixture = rootSpread study
    original = refinedMesh (spreadRefined fixture)

-- | A side profile along the wing's middle, continuing into the selected body
-- panels. Choose the layer whose original material normal points up, using
-- ownership rather than welding coincident samples from the two layers.
-- Sorting uses the original straight profile, not the deformed position.
rootProfile :: CraneRoot -> MaterialMesh -> Either SpreadError [V3]
rootProfile study mesh = do
  unless (triangles mesh == triangles original && map sampleMaterial (samples mesh) == map sampleMaterial (samples original)) (Left (SpreadError "a root profile needs unchanged material identities"))
  faces <- first (SpreadError . explain) (frameFaces (surfaceFrame (spreadSource fixture)))
  let region = S.union (spreadMoving fixture) (rootNeighbours study)
      upper = S.fromList [faceId f | f <- faces, S.member (faceId f) region, let V3 _ _ z = polygonNormal (faceCorners f), z > 0]
      vertices (a, b, c) = [a, b, c]
      selected = S.fromList [v | (tri, owner) <- zip (triangles mesh) (refinedPanels (spreadRefined fixture)), S.member owner upper, v <- vertices tri]
      line = [(y, position q) | (i, (p, q)) <- zip [0 ..] (zip (samples original) (samples mesh)), S.member i selected, let V3 x y _ = position p, abs (x - 1) < 1e-9]
  pure (map snd (sortOn (negate . fst) line))
  where
    fixture = rootSpread study
    original = refinedMesh (spreadRefined fixture)

-- | A root spring need not achieve its preferred angle. Preserve the other
-- crease angles instead, and retain the earlier length/contact/hold gates.
-- Solver convergence is separate: a plausible endpoint can still be unsettled.
rootAccepted :: CraneRoot -> Relaxation -> MaterialMesh -> Either SpreadError Bool
rootAccepted study result mesh = do
  contact <- spreadCheck fixture mesh
  creases <- originalCreaseError study mesh
  pure (converged result && maxLengthError mesh <= 1e-5 && spreadHeldError fixture mesh == 0 && creases < 1e-5 && contactPassed contact)
  where
    fixture = rootSpread study
