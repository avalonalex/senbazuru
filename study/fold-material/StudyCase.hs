-- | Authored angle states for the material-study gallery. A base is a reusable
-- folded starting shape; a flap is a panel that turns about one crease.
-- See docs/glossary.md for mountain and valley conventions.
--
-- A case references an ordinary FOLD crease pattern and supplies a complete
-- angle list for each named state, in that source file's edge order. This keeps
-- the study out of the business of inferring a folding sequence from a picture.
-- The existing folding code checks shared vertices AND crease angles. Its
-- returned cut pattern owns the face ids used here, not the original input.
--
-- We hold the largest panel still unless the case supplies a material point
-- inside another panel. A petal's largest panel is its moving tip, so that
-- case anchors the stationary base instead. Each
-- convex panel is triangulated, then every triangle is split into four. Shared
-- edge midpoints have shared ids, including across creases: lighting may split
-- there, but the material must not. These midpoints subdivide an already rigid
-- panel; they never interpolate between folding states.
--
-- This first case format supports convex panels of a unit square. It does not
-- solve bending, thickness, or motion between the supplied states. Optional
-- named panel requirements go through PanelContact in buildCasePose; buildPose
-- constructs geometry alone so tests can also inspect unconstrained states.
-- buildCaseSequence exports checked unrefined panels and coplanar orders as
-- ordinary FOLD, so the production renderer needs no study-specific reader.
module StudyCase
  ( CaseSpec (..),
    PoseSpec (..),
    StudyPose (..),
    poseFrame,
    poseOrders,
    CaseError (..),
    buildPose,
    buildCasePose,
    buildCaseFrame,
    buildCaseSequence,
  )
where

import Control.Monad (unless)
import Data.Aeson (FromJSON (..), withObject, (.:), (.:?))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (maximumBy)
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Set qualified as S
import Data.Text (Text)
import FoldMaterial
import PanelContact
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (Crease (..), Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), FaceOrder (..), FoldFile (..), Frame (..), Stacking (..), emptyFrame)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, signedArea, strictlyInside)
import Senbazuru.Geometry.Rigid (inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)
import Senbazuru.Origami.Surface qualified as Paper

data CaseSpec = CaseSpec
  { caseId :: !String,
    caseTitle :: !Text,
    caseSource :: !FilePath,
    caseDescription :: !Text,
    caseSteps :: ![PoseSpec],
    -- | A point strictly inside the panel held in its original position.
    caseFixedPanel :: !(Maybe (Double, Double)),
    caseContact :: !(Maybe ContactSpec)
  }
  deriving stock (Eq, Show)

instance FromJSON CaseSpec where
  parseJSON = withObject "study case" $ \o -> CaseSpec <$> o .: "id" <*> o .: "title" <*> o .: "source" <*> o .: "description" <*> o .: "steps" <*> o .:? "fixedPanel" <*> o .:? "contact"

data PoseSpec = PoseSpec
  { poseLabel :: !Text,
    poseAngles :: ![Double]
  }
  deriving stock (Eq, Show)

instance FromJSON PoseSpec where
  parseJSON = withObject "study pose" $ \o -> PoseSpec <$> o .: "label" <*> o .: "angles"

data StudyPose = StudyPose
  { -- | Unrefined, cut FOLD topology in the same stationary reference frame.
    poseSurface :: !(Paper.Surface V2),
    poseMesh :: !MaterialMesh,
    -- | One original panel id per triangle, for normals split at creases.
    posePanels :: ![Int],
    -- | Boundary and crease segments, without triangle subdivision lines.
    poseLines :: ![(V3, V3)],
    -- | Incident material panels for each feature segment, in poseLines order.
    poseLinePanels :: ![[Int]],
    -- | Whole rigid panels, before refinement, with their original material map.
    poseFaces :: ![(Int, [MaterialSample])],
    poseContact :: !(Maybe ContactCheck)
  }
  deriving stock (Eq, Show)

poseFrame :: StudyPose -> Frame
poseFrame = Paper.surfaceFrame . poseSurface

-- | The viewer's integer ids are a view of the material requirements, not a
-- second copy that can disagree with the shared surface.
poseOrders :: StudyPose -> Maybe (V3, [(Int, Int)])
poseOrders = fmap (\(axis, pairs) -> (axis, [(unFaceId a, unFaceId b) | (a, b) <- pairs])) . Paper.surfaceLayerRequirements . poseSurface

newtype CaseError = CaseError Text
  deriving stock (Eq, Show)

instance Explain CaseError where
  explain (CaseError message) = message

-- | Panel names are anchored strictly inside the original material, so face
-- renumbering during crease cutting cannot silently change an order's meaning.
-- Require every panel to be named: otherwise an omitted flap could escape all
-- contact checks. The raw buildPose remains useful for unconstrained fixtures.
buildCasePose :: Int -> CaseSpec -> Frame -> PoseSpec -> Either CaseError StudyPose
buildCasePose levels spec source step = do
  pose <- buildPoseAt (caseFixedPanel spec) levels source step
  checked <- traverse (check pose) (caseContact spec)
  paper <- case checked of
    Nothing -> Right (poseSurface pose)
    Just (_, (axis, pairs)) -> first (CaseError . explain) (Paper.withLayerRequirements axis [(FaceId a, FaceId b) | (a, b) <- pairs] (poseSurface pose))
  pure pose {poseSurface = paper, poseContact = fmap fst checked}
  where
    check pose requirements = do
      resolved <- mapM (resolve (poseFaces pose)) (namedPanels requirements)
      let ids = map fst resolved
      unless (length ids == length (poseFaces pose) && length ids == S.size (S.fromList ids)) $
        Left (CaseError "contact declarations must name every material panel exactly once")
      report <- first (CaseError . explain) (checkPanelContact (orderDirection requirements) (panelOrders requirements) (map snd resolved))
      let idsByName = M.fromList [(panelName panel, i) | (i, panel) <- resolved]
          orders = [(i, j) | (a, b) <- panelOrders requirements, Just i <- [M.lookup a idsByName], Just j <- [M.lookup b idsByName]]
      pure (report, (orderDirection requirements, orders))
    resolve faces (PanelTag name point@(V2 u v))
      | any (\x -> isNaN x || isInfinite x) [u, v] = Left (CaseError ("panel " <> name <> " needs a finite material point"))
      | otherwise = case [(i, Panel name (map position ps)) | (i, ps) <- faces, strictlyInside 1e-10 (outline ps) point] of
          [found] -> Right found
          _ -> Left (CaseError ("panel " <> name <> " needs a point strictly inside exactly one material face"))
    outline ps = let ring2 = [V2 (materialU p) (materialV p) | p <- ps] in if signedArea ring2 < 0 then reverse ring2 else ring2

buildPose :: Int -> Frame -> PoseSpec -> Either CaseError StudyPose
buildPose = buildPoseAt Nothing

buildPoseAt :: Maybe (Double, Double) -> Int -> Frame -> PoseSpec -> Either CaseError StudyPose
buildPoseAt anchor levels source step = do
  unless (levels >= 0 && levels <= 5) (Left (CaseError "study subdivision level must be between 0 and 5"))
  unless (length (poseAngles step) == length (edgesVertices source)) $
    Left (CaseError ("state needs " <> tshow (length (edgesVertices source)) <> " angles, one per source edge"))
  folded <- first (CaseError . explain) (foldFrameWith source {edgesFoldAngle = poseAngles step, frameTitle = Just (poseLabel step)})
  let sheet = (foldedPattern folded) {facesVertices = facesVertices (foldedFrame folded)}
  faces <- first (CaseError . explain) (frameFaces sheet)
  flat <- first (CaseError . explain) (frameVertices sheet)
  unless (all inside flat) (Left (CaseError "study material coordinates must lie in the unit square at z = 0"))
  unless (abs (sum (map faceArea faces) - 1) < 1e-9) (Left (CaseError "study panels must cover one unit of material area"))
  mapM_ convex faces
  fixed <- case anchor of
    Nothing -> case faces of
      [] -> Left (CaseError "study needs at least one panel")
      _ -> Right (maximumBy (comparing stationaryRank) faces)
    Just (u, v) -> do
      unless (all (\x -> not (isNaN x || isInfinite x)) [u, v]) $
        Left (CaseError "fixed panel needs a finite material point")
      case [face | face <- faces, strictlyInside 1e-10 [V2 x y | V3 x y _ <- faceCorners face] (V2 u v)] of
        [face] -> Right face
        _ -> Left (CaseError "fixed panel needs a point strictly inside exactly one material face")
  placement <- maybe (Left (CaseError "fixed panel has no folding transform")) Right (IM.lookup (unFaceId (faceId fixed)) (foldedPlacements folded))
  paper <- first (CaseError . explain) (Paper.surfaceFromFolded folded >>= Paper.transformSurface (inverse placement))
  (mesh, trianglePanels) <- first (CaseError . explain) (Paper.refineSurface levels paper)
  features <- first (CaseError . explain) (Paper.surfaceFeatures paper)
  panels <- first (CaseError . explain) (Paper.surfacePanelSamples paper)
  let lines3 = [(creaseStart edge, creaseEnd edge) | (edge, _) <- features]
      owners = [map unFaceId ids | (_, ids) <- features]
  pure (StudyPose paper mesh (map unFaceId trianglePanels) lines3 owners [(unFaceId fid, ps) | (fid, ps) <- panels] Nothing)
  where
    inside (V3 u v z) = u >= 0 && u <= 1 && v >= 0 && v <= 1 && z == 0

-- | A checked pose as ordinary FOLD, using the original panels rather than
-- the viewer's subdivided triangles. Standard faceOrders describe coplanar
-- material only: expand the study's order chains first, then keep the pairs
-- actually touching over an area. The renderer must obtain separated panels'
-- viewing order from geometry, not these material requirements.
buildCaseFrame :: CaseSpec -> Frame -> PoseSpec -> Either CaseError Frame
buildCaseFrame spec source step = do
  pose <- buildCasePose 0 spec source step
  unless (maybe False contactPassed (poseContact pose)) $
    Left (CaseError "FOLD sequence export needs passing panel contact and order checks")
  let frame = poseFrame pose
      (axis, orders) = fromMaybe (V3 0 0 1, []) (poseOrders pose)
      reach pairs =
        let extended = S.union pairs (S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b'])
         in if extended == pairs then pairs else reach extended
      implied = reach (S.fromList orders)
  faces <- first (CaseError . explain) (frameFaces frame)
  let known = IM.fromList [(unFaceId (faceId face), face) | face <- faces]
      relations =
        [ FaceOrder (faceId lower) (faceId upper) (if dot (polygonNormal (faceCorners upper)) axis > 0 then Below else Above)
          | (a, b) <- S.toList implied,
            Just lower <- [IM.lookup a known],
            Just upper <- [IM.lookup b known],
            coplanarContact lower upper
        ]
      active assignment angle
        | assignment == Flat && abs angle > 1e-10 = if angle < 0 then Mountain else Valley
        | otherwise = assignment
  pure frame {faceOrders = relations, edgesAssignment = zipWith active (edgesAssignment frame) (edgesFoldAngle frame)}

-- | The study manifest stops at this boundary. Ordinary CLI readers need only
-- the resulting self-contained FOLD frames, with no frame inheritance or
-- knowledge of study panel names. A metadata-only key frame is not a step.
buildCaseSequence :: CaseSpec -> FoldFile -> Either CaseError FoldFile
buildCaseSequence spec source = do
  frames <- traverse (buildCaseFrame spec (keyFrame source)) (caseSteps spec)
  pure
    source
      { fileCreator = Just "senbazuru material study",
        fileTitle = Just (caseTitle spec <> " folding sequence"),
        fileDescription = Just (caseDescription spec),
        fileClasses = ["diagrams"],
        keyFrame = emptyFrame,
        otherFrames = frames
      }

coplanarContact :: Face -> Face -> Bool
coplanarContact a b = case faceCorners a of
  [] -> False
  origin : _ -> case normalize (polygonNormal (faceCorners a)) of
    Nothing -> False
    Just normal@(V3 nx ny nz) ->
      let flatten (V3 x y z)
            | abs nx >= max (abs ny) (abs nz) = V2 y z
            | abs ny >= abs nz = V2 x z
            | otherwise = V2 x y
          outline face = let ring2 = map flatten (faceCorners face) in if signedArea ring2 < 0 then reverse ring2 else ring2
       in all ((< 1e-9) . abs . dot normal . (^-^ origin)) (faceCorners b)
            && abs (signedArea (clipConvex (outline a) (outline b))) > 1e-12

-- | Equal-area panels occur in the half/quarter folds. Hold the lowest, then
-- leftmost panel still so their angle states agree with the original controls.
stationaryRank :: Face -> (Double, Double, Double)
stationaryRank face =
  let points = faceCorners face
      count = fromIntegral (length points)
   in (faceArea face, negate (sum [y | V3 _ y _ <- points] / count), negate (sum [x | V3 x _ _ <- points] / count))

faceArea :: Face -> Double
faceArea face = abs (sum [x * w - y * z | (V3 x y _, V3 z w _) <- ring (faceCorners face)]) / 2

ring :: [a] -> [(a, a)]
ring [] = []
ring xs@(a : rest) = zip xs (rest ++ [a])

convex :: Face -> Either CaseError ()
convex face = do
  let corners = faceCorners face
      sides = ring corners
      turns = [z | (a, b) <- sides, c <- corners, let V3 _ _ z = cross (b ^-^ a) (c ^-^ a)]
  unless (faceArea face > 0 && (all (>= (-1e-12)) turns || all (<= 1e-12) turns)) $
    Left (CaseError ("study panel " <> tshow (unFaceId (faceId face)) <> " must be convex"))
