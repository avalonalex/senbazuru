-- | Separate the holds from the material preference at a crane wing's root.
-- A root is the line where the wing meets the body. The earlier experiment
-- fixes a whole strip there at 30 degrees, so changing a crease spring cannot
-- change that strip's direction. Here the tip grip stays identical while the
-- root strip and then the body panels across the root can be released.
-- See docs/glossary.md for material coordinates, panels and rest angles.
--
-- The root is the wing crease CraneWing adds, at folded y = 1/4 unless a study
-- moves it ('craneRootAt'): four segments there, eight above the wing's widest
-- point, each with one body panel across it.
--
-- A spring's rest angle is a preference, not an exact hold. The authored
-- wing-root edges therefore have measured achieved angles, separate from the
-- original mountain/valley creases which this bounded study keeps folded.
-- Making a spring weaker need not make a smoother surface: rotation can become
-- cheaper at that one line than in the surrounding panel. No rendering change
-- participates in these comparisons, and no numerical iterate is a motion.
module CraneRoot
  ( RootControl (..),
    CraneRoot (..),
    craneRoot,
    craneRootAt,
    rigidBase,
    rootAngles,
    originalCreaseError,
    rootBodyMovement,
    largestDisplacement,
    heldComparison,
    rootProfile,
    rootAccepted,
  )
where

import Control.Monad (unless)
import CraneSpread
import CraneWing (buildCraneWingAt, craneHinge, craneHingeY, craneWidest, studyHinge)
import Data.Aeson (Value, object, (.=))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Set qualified as S
import Data.Text (Text)
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Query (Crease (..), Face (..), frameFaces)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface

data RootControl = HeldRoot | ReleasedRoot | WeakerRoot | FlatRoot | FreeBody
  deriving stock (Eq, Show)

data CraneRoot = CraneRoot
  { rootSpread :: !CraneSpread,
    rootEdges :: !(S.Set EdgeId),
    rootNeighbours :: !(S.Set FaceId),
    -- | The folded line y the wing turns about, and the wing's widest point
    -- ('CraneWing').
    rootHingeY :: !Double,
    rootWidest :: !Double
  }
  deriving stock (Show)

-- | Every comparison refines the same eight source panels. Four are the
-- wing; four lie directly across its root edges. All vertices incident to
-- any OTHER panel remain held, even if also used by a released panel. Thus
-- the patch's distant boundary stays attached to the unchanged crane.
craneRoot :: Frame -> Int -> RootControl -> Either SpreadError CraneRoot
craneRoot = craneRootAt studyHinge

-- | The same controls about a wing creased along the folded line y = @hingeY@.
craneRootAt :: Double -> Frame -> Int -> RootControl -> Either SpreadError CraneRoot
craneRootAt hingeY source level control = do
  creased <- first SpreadError (buildCraneWingAt hingeY source)
  fixture <- craneSpreadFromWing WingAndRootNeighbours creased level 20
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
  unless (S.size edges == length (craneHinge creased) && S.size nearby == S.size edges) $
    Left (SpreadError "expected a wing-root edge for every wing-crease segment and one neighbouring body panel across each")
  pure (CraneRoot fixture {spreadPins = pins, spreadHinges = map change (spreadHinges fixture)} edges nearby (craneHingeY creased) (craneWidest creased))

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

-- | How far one endpoint lies from another: the largest distance between the
-- positions of matching samples. Samples match by index, so both must hold the
-- same material in the same order; 'Nothing' where they do not, since pairing
-- them would measure between different paper. 'rootBodyMovement' measures the
-- body against where it started; this measures all the paper against another
-- solve, which is how a body gallery asks whether holding the body changed the
-- shape (owner decision 39).
largestDisplacement :: [Sample V2] -> [Sample V2] -> Maybe Double
largestDisplacement these those
  | map sampleMaterial these /= map sampleMaterial those = Nothing
  | otherwise = Just (maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) these those))

-- | How far each released control's endpoint lies from the held control's,
-- as a body gallery records it on every run (owner decision 39): in sheet
-- units, in pixels at 600 per sheet unit, and at the page's own scale where
-- the gallery draws its paper. Each endpoint is a control's id, whether its
-- gallery accepts it, and its samples. A gallery's controls all solve one
-- mesh, so an endpoint that cannot be compared is a fault, recorded rather
-- than fatal: by then the gallery has run for hours.
heldComparison :: Maybe Double -> String -> [(String, Bool, [Sample V2])] -> Value
heldComparison scale heldId endpoints = case [(accepted, s) | (key, accepted, s) <- endpoints, key == heldId] of
  [(accepted, held)] -> object ["held" .= heldId, "heldAccepted" .= accepted, "released" .= [entry held e | e@(key, _, _) <- endpoints, key /= heldId]]
  _ -> object ["held" .= heldId, "error" .= ("the gallery has no single endpoint of that id" :: Text)]
  where
    entry held (key, accepted, s) = object (["id" .= key, "accepted" .= accepted] ++ maybe ["error" .= ("it is not on the held control's mesh" :: Text)] measured (largestDisplacement held s))
    measured d = ["largestDisplacement" .= d, "pixelsAt600" .= (600 * d)] ++ ["pixelsAtPageScale" .= (k * d) | Just k <- [scale]]

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

-- | Turn a released control's base as one piece. Above the wing's widest
-- point the paper between it and the hinge is four layers deep ('CraneWing');
-- a released control solved with it bending as a sheet stalled at y = 0.376
-- (#455). Pin every vertex of that base where the flat crane's base lands
-- turned by @theta@ degrees about the hinge, the way the root strip turns in
-- 'craneSpread', and start from @solved@ with the base moved there. A vertex
-- the control already holds keeps its hold, so a held control comes back
-- unchanged. With the hinge below the widest point, no vertex of the turning
-- wing lies at or above it: there is no base, and nothing changes either.
rigidBase :: Double -> CraneRoot -> MaterialMesh -> CraneRoot
rigidBase theta study solved
  | IM.null base = study
  | otherwise = study {rootSpread = fixture {spreadPins = IM.union (spreadPins fixture) base, spreadMesh = solved {samples = placed}}}
  where
    fixture = rootSpread study
    flat = refinedMesh (spreadRefined fixture)
    hingeY = rootHingeY study
    turn = theta * pi / 180
    corners (a, b, c) = [a, b, c]
    wing = S.fromList [v | (tri, owner) <- zip (triangles flat) (refinedPanels (spreadRefined fixture)), S.member owner (spreadMoving fixture), v <- corners tri]
    -- The hinge's own vertices stay where the body holds them.
    base =
      IM.fromList
        [ (i, V3 x (hingeY - len * cos turn) (negate (len * sin turn)))
          | (i, p) <- zip [0 ..] (samples flat),
            S.member i wing,
            IM.notMember i (spreadPins fixture),
            let V3 x y _ = position p,
            y >= rootWidest study - 1e-9,
            let len = hingeY - y,
            len > 1e-12
        ]
    placed = [maybe q (\target -> q {position = target}) (IM.lookup i base) | (i, q) <- zip [0 ..] (samples solved)]
