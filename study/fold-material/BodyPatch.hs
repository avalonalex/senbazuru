-- | A free-boundary specimen cut from the mapped crane, not a whole-crane pose.
-- Keep the eight central panels and their eight wing neighbours. Removing the
-- rest removes its loads and contacts too; the neck/tail interface landmarks
-- measure attachment response, not motion of an attached neck or tail.
-- See docs/glossary.md for material coordinates, panels and rest angles.
--
-- Three exact holds prescribe opening: the material centre and two opposite
-- wing attachments, turned about that centre without changing their radius.
-- All internal physical creases here are mapped candidate opening folds, so
-- their original angles are preferences, not exact endpoint requirements.
-- Uncreased edges keep their zero-angle bending cost. Nothing welds touching
-- material. Expand the FULL crane's order before extracting the patch: an
-- omitted intermediate layer must not erase the order of two retained ones.
module BodyPatch
  ( BodyPatch (..),
    bodyPatch,
    patchAccepted,
    patchAngles,
    patchLandmarks,
  )
where

import Control.Monad (unless)
import CranePocket
import CraneSpread
import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import FoldBending
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Query (Crease (..), Face (..), edgeKey, frameFaces, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (contactPassed)
import Senbazuru.Origami.Surface

data BodyPatch = BodyPatch
  { patchSpread :: !CraneSpread,
    patchFaces :: ![FaceId],
    patchCore :: ![FaceId],
    patchEdges :: ![EdgeId],
    patchVertices :: ![VertexId],
    patchMarks :: ![(Text, Int)],
    patchDegrees :: !Double,
    patchLevel :: !Int
  }
  deriving stock (Show)

bodyPatch :: PocketMap -> Int -> Double -> Either SpreadError BodyPatch
bodyPatch atlas level degrees = do
  unless (level `elem` [0, 1] && not (isNaN degrees || isInfinite degrees) && degrees >= 0 && degrees <= 10) $
    Left (SpreadError "body patch needs refinement 0 or 1 and an opening from 0 to 10 degrees")
  let original = pocketSurface atlas
      source = surfaceFrame original
      core = S.fromList (regionFaces atlas BodyCore)
      wingFaces = S.fromList (regionFaces atlas WingA ++ regionFaces atlas WingB)
      chosen = S.toAscList (S.union core (S.fromList [f | e <- pocketEdges atlas, any (`S.member` core) (pocketOwners e), f <- pocketOwners e, S.member f wingFaces]))
      faceMap = M.fromList (zip chosen (map FaceId [0 ..]))
      rings = [ring | (fid, ring) <- zip (map FaceId [0 ..]) (facesVertices source), M.member fid faceMap]
      used = S.toAscList (S.fromList (concat rings))
      vertexMap = M.fromList (zip used (map VertexId [0 ..]))
      allPoints = M.fromList (zip (map VertexId [0 ..]) (surfaceSamples original))
      incidence = M.fromListWith (+) [(edgeKey a b, 1 :: Int) | ring <- rings, (a, b) <- ringEdges ring]
      kept = [e | e <- pocketEdges atlas, let c = pocketCrease e, M.member (edgeKey (creaseFrom c) (creaseTo c)) incidence]
      sourceEdges = map (creaseId . pocketCrease) kept
      assignment e = let c = pocketCrease e in if M.lookup (edgeKey (creaseFrom c) (creaseTo c)) incidence == Just 1 then Border else creaseAssignment c
  unless (length chosen == 16 && length (filter (`S.member` core) chosen) == 8) $
    Left (SpreadError "body patch needs eight central panels and eight wing neighbours")
  -- Refuse an accidental extension into folds whose original angles ought to
  -- remain controlled. This makes the selective policy part of the fixture.
  unless (all (\e -> assignment e `notElem` [Mountain, Valley] || pocketRole e == CandidateOpening) kept) $
    Left (SpreadError "body patch contains a physical crease outside the mapped opening set")
  points <- traverse (lookupValue "missing patch material vertex" allPoints) used
  faces <- traverse (traverse (lookupValue "missing patch vertex id" vertexMap)) rings
  edges <- traverse (\e -> let c = pocketCrease e in (,) <$> lookupValue "missing patch edge start" vertexMap (creaseFrom c) <*> lookupValue "missing patch edge end" vertexMap (creaseTo c)) kept
  originalFaces <- checked (frameFaces source)
  let normals = M.fromList [(faceId f, polygonNormal (faceCorners f)) | f <- originalFaces]
  fullOrders <- traverse (directed normals) (faceOrders source)
  let orders = [(a', b') | (a, b) <- S.toAscList (closure (S.fromList fullOrders)), Just a' <- [M.lookup a faceMap], Just b' <- [M.lookup b faceMap]]
      localNormals = M.fromList [(fid', n) | (fid, fid') <- M.toList faceMap, Just n <- [M.lookup fid normals]]
  signed <- traverse (signedOrder localNormals) orders
  let frame =
        emptyFrame
          { frameClasses = ["foldedForm"],
            frameAttributes = ["3D"],
            verticesCoords = map (coords . position) points,
            facesVertices = faces,
            edgesVertices = edges,
            edgesAssignment = map assignment kept,
            faceOrders = signed,
            frameExtras = KM.singleton "senbazuru:material_coords" (toJSON [[materialU p, materialV p] | p <- points])
          }
  sheet <- checked (surfaceFromFrame frame >>= requireMaterialCoordinates)
  features <- checked (surfaceFeatures sheet)
  let targets = M.fromList [(creaseId c, if creaseAssignment c == Mountain then -pi else pi) | (c, _) <- features, creaseAssignment c `elem` [Mountain, Valley]]
  (refined, hinges) <- checked (buildSurfaceHinges (Bending 1 0.2) level sheet targets)
  let base = refinedMesh refined
      a = sqrt 2 / 4
      b = 1 - a
      resolve (name, target) = case [i | (i, p) <- zip [0 ..] (samples base), norm (sampleMaterial p ^-^ target) < 1e-9] of
        [i] -> Right (name, i)
        _ -> Left (SpreadError ("body patch needs one material landmark for " <> name))
  marks <- traverse resolve [("centre", V2 0.5 0.5), ("wing-a", V2 a b), ("wing-b", V2 b a), ("tail", V2 a a), ("neck", V2 b b)]
  centre <- lookupValue "missing material centre" (M.fromList marks) "centre" >>= lookupValue "missing centre position" (M.fromList (zip [0 ..] (map position (samples base))))
  let V3 _ cy _ = centre
      angle = degrees * pi / 180
      -- This is only an initial guess. It may stretch or cross; the numerical
      -- endpoint must earn acceptance. It is never a folding animation.
      move p
        | degrees == 0 = p
        | otherwise =
            let V3 x y z = position p
                V2 u v = sampleMaterial p
             in p {position = V3 x (cy + (y - cy) * cos angle) (z - (v - u) / sqrt 2 * sin angle)}
      moved = map move (samples base)
      held = S.fromList [i | (name, i) <- marks, name `elem` ["centre", "wing-a", "wing-b"]]
      pins = IM.fromList [(i, position p) | (i, p) <- zip [0 ..] moved, S.member i held]
      fixture = CraneSpread sheet refined base {samples = moved} pins S.empty (S.fromList (M.elems faceMap)) hinges orders held
  unless (componentCount base == 1 && IM.size pins == 3) (Left (SpreadError "body patch must be one connected specimen with three exact holds"))
  pure (BodyPatch fixture chosen [fid | (sourceId, fid) <- M.toList faceMap, S.member sourceId core] sourceEdges used marks degrees level)

-- | Soft original-angle preferences may change. All geometric and numerical
-- endpoint checks remain required. spreadCheck also checks material identity.
patchAccepted :: BodyPatch -> Relaxation -> MaterialMesh -> Either SpreadError Bool
patchAccepted study result mesh = do
  contact <- spreadCheck fixture mesh
  pure (converged result && maxLengthError mesh <= 1e-5 && componentCount mesh == 1 && spreadHeldError fixture mesh == 0 && contactPassed contact)
  where
    fixture = patchSpread study

-- | Original crane edge id, signed achieved angle and preferred angle.
patchAngles :: BodyPatch -> MaterialMesh -> Either SpreadError [(EdgeId, Double, Double)]
patchAngles study mesh = traverse measure [(eid, h) | h <- spreadHinges (patchSpread study), SurfaceCrease eid <- [hingeRole h]]
  where
    source = M.fromList (zip (map EdgeId [0 ..]) (patchEdges study))
    points = IM.fromList (zip [0 ..] (samples mesh))
    measure (eid, h) = do
      original <- lookupValue "missing source crease identity" source eid
      (angle, _) <- checked (hingeAngle h points)
      pure (original, angle, hingeRest h)

patchLandmarks :: BodyPatch -> MaterialMesh -> Either SpreadError [(Text, V3, V3)]
patchLandmarks study mesh = traverse measure (patchMarks study)
  where
    original = M.fromList (zip [0 ..] (map position (samples (refinedMesh (spreadRefined (patchSpread study))))))
    current = M.fromList (zip [0 ..] (map position (samples mesh)))
    measure (name, i) = (name,,) <$> lookupValue "missing original landmark" original i <*> lookupValue "missing endpoint landmark" current i

lookupValue :: (Ord k) => Text -> M.Map k v -> k -> Either SpreadError v
lookupValue message values key = maybe (Left (SpreadError message)) Right (M.lookup key values)

coords :: V3 -> [Double]
coords (V3 x y z) = [x, y, z]

directed :: M.Map FaceId V3 -> FaceOrder -> Either SpreadError (FaceId, FaceId)
directed normals order = do
  V3 _ _ z <- lookupValue "missing ordered panel normal" normals (orderRelativeTo order)
  pure (if (orderStacking order == Above) == (z > 0) then (orderRelativeTo order, orderFace order) else (orderFace order, orderRelativeTo order))

signedOrder :: M.Map FaceId V3 -> (FaceId, FaceId) -> Either SpreadError FaceOrder
signedOrder normals (lower, upper) = do
  V3 _ _ z <- lookupValue "missing upper panel normal" normals upper
  pure (FaceOrder lower upper (if z > 0 then Below else Above))

closure :: (Ord a) => S.Set (a, a) -> S.Set (a, a)
closure pairs = let more = S.union pairs (S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b']) in if more == pairs then pairs else closure more

checked :: (Explain e) => Either e a -> Either SpreadError a
checked = first (SpreadError . explain)
