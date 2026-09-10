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
-- We hold the largest panel still so a sequence has one reference frame. Each
-- convex panel is triangulated, then every triangle is split into four. Shared
-- edge midpoints have shared ids, including across creases: lighting may split
-- there, but the material must not. These midpoints subdivide an already rigid
-- panel; they never interpolate between folding states.
--
-- This first case format supports convex panels of a unit square. It does not
-- solve bending, thickness, collisions, or motion between the supplied states.
module StudyCase
  ( CaseSpec (..),
    PoseSpec (..),
    StudyPose (..),
    CaseError (..),
    buildPose,
  )
where

import Control.Monad (unless)
import Data.Aeson (FromJSON (..), withObject, (.:))
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (maximumBy)
import Data.Map.Strict qualified as M
import Data.Ord (comparing)
import Data.Set qualified as S
import Data.Text (Text)
import FoldMaterial
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)

data CaseSpec = CaseSpec
  { caseId :: !String,
    caseTitle :: !Text,
    caseSource :: !FilePath,
    caseDescription :: !Text,
    caseSteps :: ![PoseSpec]
  }
  deriving stock (Eq, Show)

instance FromJSON CaseSpec where
  parseJSON = withObject "study case" $ \o -> CaseSpec <$> o .: "id" <*> o .: "title" <*> o .: "source" <*> o .: "description" <*> o .: "steps"

data PoseSpec = PoseSpec
  { poseLabel :: !Text,
    poseAngles :: ![Double]
  }
  deriving stock (Eq, Show)

instance FromJSON PoseSpec where
  parseJSON = withObject "study pose" $ \o -> PoseSpec <$> o .: "label" <*> o .: "angles"

data StudyPose = StudyPose
  { poseMesh :: !Mesh,
    -- | One original panel id per triangle, for normals split at creases.
    posePanels :: ![Int],
    -- | Boundary and crease segments, without triangle subdivision lines.
    poseLines :: ![(V3, V3)]
  }
  deriving stock (Eq, Show)

newtype CaseError = CaseError Text
  deriving stock (Eq, Show)

instance Explain CaseError where
  explain (CaseError message) = message

buildPose :: Int -> Frame -> PoseSpec -> Either CaseError StudyPose
buildPose levels source step = do
  unless (levels >= 0 && levels <= 5) (Left (CaseError "study subdivision level must be between 0 and 5"))
  unless (length (poseAngles step) == length (edgesVertices source)) $
    Left (CaseError ("state needs " <> tshow (length (edgesVertices source)) <> " angles, one per source edge"))
  folded <- first (CaseError . explain) (foldFrameWith source {edgesFoldAngle = poseAngles step})
  let sheet = (foldedPattern folded) {facesVertices = facesVertices (foldedFrame folded)}
  faces <- first (CaseError . explain) (frameFaces sheet)
  flat <- first (CaseError . explain) (frameVertices sheet)
  placed <- first (CaseError . explain) (frameVertices (foldedFrame folded))
  unless (all inside flat) (Left (CaseError "study material coordinates must lie in the unit square at z = 0"))
  unless (abs (sum (map faceArea faces) - 1) < 1e-9) (Left (CaseError "study panels must cover one unit of material area"))
  mapM_ convex faces
  fixed <- case faces of
    [] -> Left (CaseError "study needs at least one panel")
    _ -> Right (maximumBy (comparing stationaryRank) faces)
  placement <- maybe (Left (CaseError "fixed panel has no folding transform")) Right (IM.lookup (unFaceId (faceId fixed)) (foldedPlacements folded))
  let points = [Sample u v (applyRigid (inverse placement) q) | (V3 u v _, q) <- zip flat placed]
      tagged = [(triangle, unFaceId (faceId face)) | face <- faces, triangle <- fan (map unVertexId (faceVertexIds face))]
      (refined, refinedFaces) = iterateSplit levels points tagged
      lookupPoint i = maybe (Left (CaseError "feature edge refers to a missing vertex")) (Right . position) (IM.lookup (unVertexId i) (IM.fromList (zip [0 ..] points)))
  lines3 <- mapM (\(a, b) -> (,) <$> lookupPoint a <*> lookupPoint b) [(a, b) | ((a, b), assignment) <- zip (edgesVertices sheet) (edgesAssignment sheet), assignment `elem` [Border, Mountain, Valley]]
  pure (StudyPose (Mesh refined (map fst refinedFaces)) (map snd refinedFaces) lines3)
  where
    inside (V3 u v z) = u >= 0 && u <= 1 && v >= 0 && v <= 1 && z == 0

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

fan :: [Int] -> [Triangle]
fan (a : b : c : rest) = (a, b, c) : fan (a : c : rest)
fan _ = []

-- | Topological edge keys avoid approximate-coordinate welding, which could
-- accidentally connect distinct pieces of paper at a folded overlap.
iterateSplit :: Int -> [Sample] -> [(Triangle, Int)] -> ([Sample], [(Triangle, Int)])
iterateSplit 0 points faces = (points, faces)
iterateSplit n points faces =
  let indexed = IM.fromList (zip [0 ..] points)
      keys = S.toList (S.fromList [ordered i j | ((a, b, c), _) <- faces, (i, j) <- [(a, b), (b, c), (c, a)]])
      midpoint (a, b) = do
        p <- IM.lookup a indexed
        q <- IM.lookup b indexed
        pure (Sample ((materialU p + materialU q) / 2) ((materialV p + materialV q) / 2) (0.5 *^ (position p ^+^ position q)))
      added = [(edge, point) | edge <- keys, Just point <- [midpoint edge]]
      ids = M.fromList (zip (map fst added) [length points ..])
      split ((a, b, c), panel) = case (M.lookup (ordered a b) ids, M.lookup (ordered b c) ids, M.lookup (ordered c a) ids) of
        (Just ab, Just bc, Just ca) -> [((a, ab, ca), panel), ((ab, b, bc), panel), ((ca, bc, c), panel), ((ab, bc, ca), panel)]
        _ -> [] -- All indices come from validated faces and previous splits.
   in iterateSplit (n - 1) (points ++ map snd added) (concatMap split faces)
  where
    ordered a b = (min a b, max a b)
