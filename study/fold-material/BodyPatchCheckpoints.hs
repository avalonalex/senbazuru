-- | Inspect positions already saved by BodyPatchGallery; never call a solver.
-- A checkpoint is a numerical iterate, not a folding instruction. This reader
-- accepts only the two 5-degree runs that exhausted all four 40-step stages:
-- their complete saved schedule makes the penalty at each point unambiguous.
-- Other budgets, early exits and incomplete histories need a different reader.
--
-- Length/contact costs use half the squared residual, like bendingEnergy.
-- FoldRelaxation's line search uses twice this total, which changes no ordering.
-- At a stage boundary compare BOTH endpoints at the arriving stage's weight;
-- comparing their stored totals would confuse a stronger penalty with an uphill
-- correction. Movement between sparse checkpoints is net displacement, never
-- the missing full proposal or a convergence certificate. Material coordinates,
-- panels and rest angles are defined in docs/glossary.md.
module BodyPatchCheckpoints
  ( SavedPoint (..),
    PatchMeasure (..),
    PatchEdge (..),
    readPatchArchive,
    measurePatch,
    checkpointWeight,
    patchCost,
    savedMovement,
    savedSchedule,
  )
where

import BodyPatch
import Control.Monad (forM, unless)
import CraneSpread
import Data.Aeson (Value (..), withArray, withObject, (.:))
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.Foldable (toList)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import Data.Text qualified as T
import FoldBending (bendingEnergy)
import FoldContact (ContactRow (..))
import FoldMaterial (meshEdges)
import FoldRelaxation (maxLengthError)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (ContactCheck)
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact

-- | Iteration zero is the supplied, potentially invalid opening guess.
data SavedPoint = SavedPoint {savedIteration :: !Int, savedMesh :: !MaterialMesh} deriving stock (Eq, Show)

data PatchEdge = PatchEdge
  { edgeVertices :: !(Int, Int),
    edgeRestLength :: !Double,
    edgeLengthChange :: !Double,
    edgeRelativeError :: !Double
  }
  deriving stock (Eq, Show)

data PatchMeasure = PatchMeasure
  { measuredPoint :: !SavedPoint,
    measuredEdges :: ![PatchEdge],
    measuredContact :: !ContactCheck,
    measuredCrease :: !Double,
    measuredPanel :: !Double,
    measuredLengthSquares :: !Double,
    measuredContactSquares :: !Double,
    measuredMinimumGap :: !(Maybe Double),
    measuredBodyDepth :: !Double
  }
  deriving stock (Eq, Show)

savedSchedule :: [Int]
savedSchedule = 0 : [offset + i | offset <- [0, 40, 80, 120], i <- [1, 2, 5, 10, 20, 40]]

-- | Weight used to ARRIVE at this snapshot (the next step may change it).
checkpointWeight :: Int -> Either SpreadError Double
checkpointWeight i
  | i >= 0 && i <= 40 = Right 1e2
  | i <= 80 && i > 40 = Right 1e4
  | i <= 120 && i > 80 = Right 1e6
  | i <= 160 && i > 120 = Right 1e8
  | otherwise = Left (SpreadError "checkpoint iteration is outside the archived four-stage run")

readPatchArchive :: Text -> BodyPatch -> Value -> Value -> Frame -> Frame -> Value -> Either SpreadError [SavedPoint]
readPatchArchive name study document single initialFrame finalFrame history = do
  unless (patchDegrees study == 5 && (name, patchLevel study) `elem` [("opening-5", 0), ("opening-5-fine", 1)]) (bad "expected one of the two saved 5-degree controls")
  record <-
    parsed
      ( withObject "body-patch archive" $ \o -> do
          expect o "iterationLimitPerStage" (40 :: Int)
          expect o "lengthWeights" ([1e2, 1e4, 1e6, 1e8] :: [Double])
          expect o "lengthTolerance" (1e-5 :: Double)
          records <- o .: "runs"
          case [r | r <- records, parseEither (withObject "run" (.: "id")) r == Right name] of
            [r] -> pure r
            _ -> fail "expected exactly one selected body-patch run"
      )
      document
  unless (record == single) (bad "combined and individual source reports disagree")
  parsed
    ( withObject
        "body-patch run"
        ( \o -> do
            expect o "degrees" (5 :: Double)
            expect o "level" (patchLevel study)
            expect o "vertices" (length (samples base))
            expect o "triangles" (length (triangles base))
            expect o "sourceFaces" (map unFaceId (patchFaces study))
            expect o "corePanels" (map unFaceId (patchCore study))
            expect o "sourceEdges" (map unEdgeId (patchEdges study))
            expect o "sourceVertices" (map unVertexId (patchVertices study))
            expect o "sourceOrders" [[unFaceId a, unFaceId b] | (a, b) <- spreadOrders fixture]
            pins <- o .: "pins" >>= traverse (withObject "pin" (\p -> (,) <$> p .: "vertex" <*> (p .: "position" >>= vector)))
            unless (pins == IM.toList (spreadPins fixture)) (fail "changed exact holds")
            expect o "iterations" (160 :: Int)
            expect o "blockedStages" ([] :: [Value])
            expect o "converged" False
            expect o "accepted" False
            expect o "equilibrium" Null
            expect o "wholeCraneChecked" False
            expect o "continuousMotionChecked" False
        )
    )
    record
  initial <- readMesh initialFrame
  final <- readMesh finalFrame
  unless (map position (samples initial) == map position (samples base)) (bad "archive initial positions differ from the declared opening guess")
  points <-
    parsed
      ( withArray
          "saved checkpoints"
          ( traverse
              ( withObject "checkpoint" $ \o -> do
                  iteration <- o .: "iteration"
                  recordedError <- o .: "maxRelativeEdgeError"
                  positions <- o .: "positions" >>= traverse vector
                  unless (length positions == length (samples base)) (fail "checkpoint vertex count changed")
                  let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) positions}
                  unless (finite recordedError && abs (recordedError - maxLengthError mesh) <= 1e-12) (fail "saved length error disagrees with positions")
                  unless (spreadHeldError fixture mesh == 0) (fail "checkpoint moves an exact hold")
                  pure (SavedPoint iteration mesh)
              )
              . toList
          )
      )
      history
  unless (map savedIteration points == savedSchedule) (bad "saved checkpoint schedule is incomplete or changed")
  case points of
    p : rest -> do
      unless (savedMesh p == initial) (bad "first checkpoint differs from saved initial FOLD")
      let lastPoint = foldl (\_ q -> q) p rest
      unless (savedMesh lastPoint == final) (bad "last checkpoint differs from saved endpoint FOLD")
    [] -> bad "empty checkpoint history"
  pure points
  where
    fixture = patchSpread study
    base = spreadMesh fixture
    readMesh frame = do
      positions <- parsed (traverse vector) (verticesCoords frame)
      unless (length positions == length (samples base)) (bad "FOLD vertex count changed")
      let mesh = base {samples = zipWith (\p q -> p {position = q}) (samples base) positions}
      -- Rebuild only the export metadata, not a solve. This binds triangles,
      -- material coordinates, source ids, assignments and derived face orders.
      expected <- materialFrame <$> spreadSurface fixture mesh
      unless (frame == expected) (bad "saved FOLD material/topology/metadata differs from the declared patch")
      pure mesh
    bad = Left . SpreadError
    expect o key expected = do actual <- o .: key; unless (actual == expected) (fail ("changed archive field: " ++ show key))

measurePatch :: BodyPatch -> SavedPoint -> Either SpreadError PatchMeasure
measurePatch study point = do
  report <- spreadCheck fixture mesh
  (crease, panel) <- checked (bendingEnergy (spreadHinges fixture) mesh)
  model <- checked (Contact.prepareContact 0 (V3 0 0 1) (spreadContactOrders fixture) owners (spreadMesh fixture))
  rows <- checked (Contact.orderedContacts model mesh)
  edges <- forM (meshEdges mesh) $ \(i, j) -> do
    a <- vertex i
    b <- vertex j
    let rest = norm (sampleMaterial b ^-^ sampleMaterial a)
        change = norm (position b ^-^ position a) - rest
    unless (rest > 0 && finite rest && finite change) (Left (SpreadError "invalid material edge in checkpoint"))
    pure (PatchEdge (i, j) rest change (abs (change / rest)))
  zs <- traverse (fmap (\p -> let V3 _ _ z = position p in z) . vertex) [i | ((a, b, c), owner) <- zip (triangles mesh) owners, owner `elem` patchCore study, i <- [a, b, c]]
  pure (PatchMeasure point edges report crease panel (sum [edgeLengthChange e ^ (2 :: Int) | e <- edges]) (sum [min 0 (contactGap r) ^ (2 :: Int) | r <- rows]) (minimumMaybe (map contactGap rows)) (maybe 0 (\lo -> maximum (lo : zs) - lo) (minimumMaybe zs)))
  where
    fixture = patchSpread study
    mesh = savedMesh point
    owners = refinedPanels (spreadRefined fixture)
    vertices = IM.fromList (zip [0 ..] (samples mesh))
    vertex i = maybe (Left (SpreadError "checkpoint edge lost a material vertex")) Right (IM.lookup i vertices)
    minimumMaybe [] = Nothing
    minimumMaybe (x : xs) = Just (foldr min x xs)

-- | Half the line-search objective, without the numerical step damping.
patchCost :: Double -> PatchMeasure -> Double
patchCost weight m = weight * measuredLengthSquares m / 2 + 100 * weight * measuredContactSquares m / 2 + measuredCrease m + measuredPanel m

savedMovement :: SavedPoint -> SavedPoint -> Either SpreadError Double
savedMovement a b = do
  let before = savedMesh a; after = savedMesh b
  unless (triangles before == triangles after && map sampleMaterial (samples before) == map sampleMaterial (samples after)) (Left (SpreadError "checkpoint movement needs identical material identities"))
  pure (maximum (0 : zipWith (\p q -> norm (position p ^-^ position q)) (samples before) (samples after)))

vector :: [Double] -> Parser V3
vector [x, y, z] | all finite [x, y, z] = pure (V3 x y z)
vector _ = fail "checkpoint needs three finite coordinates per vertex"

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

parsed :: (a -> Parser b) -> a -> Either SpreadError b
parsed parser = first (SpreadError . T.pack) . parseEither parser

checked :: (Explain e) => Either e a -> Either SpreadError a
checked = first (SpreadError . explain)
