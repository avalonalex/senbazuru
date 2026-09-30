-- | A solved pose's finer level, taken from its gallery's own finer solve
-- (owner decision 29, 2026-09-30).
--
-- The paper screen judges false creases on a pose's mesh and on the pose
-- /made again/ one level finer, with every triangle split into four
-- ("ScreenReport", docs/glossary.md). A folded or placed pose is made again
-- by repeating its construction on the finer sheet. A solved pose could be
-- made again only by solving it again, and decision 27 does not, because a
-- new solve is a new answer and may be another shape. So a solved pose's
-- finer level is not measured, and it cannot pass. Some galleries solve the
-- same control on the finer mesh anyway, to see whether refining changes the
-- answer. Decision 29 counts that solve as the pose made again where it is
-- shown to be the same pose:
--
-- 1. its mesh is the pose's mesh with every triangle split into four;
-- 2. it solves the same control;
-- 3. the two solves agree at every vertex of the coarser mesh within the
--    floor limit, 'floorLimitPixels' at 'pixelsPerSheet'.
--
-- 'sameFinerPose' checks the first and the third. The second is the
-- gallery's to say, since only the gallery knows its controls, so each
-- gallery names its pairs.
--
-- What a newcomer would get wrong is matching the two meshes by vertex
-- number. The finer mesh numbers its vertices its own way; what the two
-- share is the flat sheet. So a coarse triangle's corners and edge midpoints
-- are looked up by /material point/, each of which must be exactly one
-- vertex of the finer mesh, and the finer mesh must hold the four triangles
-- each coarse triangle splits into and nothing else.
module FinerSolve
  ( SameFinerPose (..),
    FinerSolveRefusal (..),
    sameFinerPose,
    withFinerSolve,
    Pending (..),
    finishReports,
  )
where

import Control.Monad (forM, unless)
import Data.Aeson (Value, object, (.=))
import Data.Aeson.Types (Pair)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Map.Strict qualified as M
import Data.Ord (Down (..))
import Data.Set qualified as S
import Data.Text (Text)
import ScreenReport (Screen (..), floorLimitPixels, pixelsPerSheet)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))

-- | A finer solve shown to be the same pose one level finer: how far apart
-- the two solves are at worst, over the coarser mesh's vertices, in pixels
-- at the screen's scale.
newtype SameFinerPose = SameFinerPose {finerApartPixels :: Double}
  deriving stock (Eq, Show)

-- | Why a finer solve does not count as the pose made again. Each names the
-- coarse triangle or vertex where the check stopped.
data FinerSolveRefusal
  = -- | The finer mesh has the second number of triangles, where four for
    -- each of the coarser mesh's would be the first.
    FinerTriangleCount !Int !Int
  | -- | This coarse triangle names a vertex its mesh does not have.
    UnknownCoarseVertex !Int
  | -- | A corner or edge midpoint of this coarse triangle is no vertex of
    -- the finer mesh.
    MissingFinerPoint !Int
  | -- | More than one vertex of the finer mesh lies at a corner or edge
    -- midpoint of this coarse triangle.
    AmbiguousFinerPoint !Int
  | -- | The finer mesh lacks one of the four triangles this coarse triangle
    -- splits into.
    MissingFinerTriangle !Int
  | -- | At this coarse vertex the two solves are this many pixels apart,
    -- more than the floor limit.
    SolvesApart !Int !Double
  deriving stock (Eq, Show)

instance Explain FinerSolveRefusal where
  explain = \case
    FinerTriangleCount expected actual -> "the finer mesh has " <> tshow actual <> " triangles, not " <> tshow expected <> ", four for each of this mesh's, so it is not this mesh split into four"
    UnknownCoarseVertex t -> "triangle " <> tshow t <> " names a vertex its mesh does not have"
    MissingFinerPoint t -> "a corner or edge midpoint of triangle " <> tshow t <> " is no vertex of the finer mesh, so the finer mesh is not this mesh split into four"
    AmbiguousFinerPoint t -> "more than one vertex of the finer mesh lies at a corner or edge midpoint of triangle " <> tshow t <> ", so the two meshes cannot be matched on the flat sheet"
    MissingFinerTriangle t -> "the finer mesh lacks one of the four triangles that triangle " <> tshow t <> " splits into, so it is not this mesh split into four"
    SolvesApart v pixels -> "at vertex " <> tshow v <> " the two solves are " <> num pixels <> " px apart, more than the floor limit of " <> num floorLimitPixels <> " px, so the finer solve may be another shape"

-- | Two points of the flat sheet closer than this, in sheet units, are one
-- point: far below any mesh's spacing, and far above the rounding in a
-- midpoint worked out from its ends.
samePoint :: Double
samePoint = 1e-9

-- | Whether @fine@ is @coarse@'s pose one level finer, by conditions 1 and 3
-- above, and if so how far apart the two are at worst.
sameFinerPose :: MaterialMesh -> MaterialMesh -> Either FinerSolveRefusal SameFinerPose
sameFinerPose coarse fine = do
  let expected = 4 * length (triangles coarse)
  unless (length (triangles fine) == expected) (Left (FinerTriangleCount expected (length (triangles fine))))
  matched <- concat <$> forM (zip [0 ..] (triangles coarse)) split
  -- A vertex shared by several coarse triangles is matched once for each;
  -- every match finds the same finer vertex, so keeping one loses nothing.
  let apart = [(v, pixelsPerSheet * norm (position c ^-^ position f)) | (v, (c, f)) <- IM.toList (IM.fromList matched)]
  case sortOn (Down . snd) apart of
    (v, pixels) : _ | pixels > floorLimitPixels -> Left (SolvesApart v pixels)
    (_, pixels) : _ -> Right (SameFinerPose pixels)
    [] -> Right (SameFinerPose 0)
  where
    coarseSamples = IM.fromList (zip [0 ..] (samples coarse))
    fineSamples = zip [0 :: Int ..] (samples fine)
    fineTriangles = S.fromList [S.fromList [a, b, c] | (a, b, c) <- triangles fine]
    -- One coarse triangle: its corners and edge midpoints as finer vertices,
    -- and the four triangles it splits into among the finer mesh's. The
    -- result pairs each corner's coarse sample with its finer one.
    split (t, (a, b, c)) = do
      (sa, sb, sc) <- maybe (Left (UnknownCoarseVertex t)) Right ((,,) <$> IM.lookup a coarseSamples <*> IM.lookup b coarseSamples <*> IM.lookup c coarseSamples)
      let (ma, mb, mc) = (sampleMaterial sa, sampleMaterial sb, sampleMaterial sc)
      (ia, fa) <- finerAt t ma
      (ib, fb) <- finerAt t mb
      (ic, fc) <- finerAt t mc
      (iab, _) <- finerAt t (midpoint ma mb)
      (ibc, _) <- finerAt t (midpoint mb mc)
      (ica, _) <- finerAt t (midpoint mc ma)
      let pieces = [[ia, iab, ica], [iab, ib, ibc], [ica, ibc, ic], [iab, ibc, ica]]
      unless (all ((`S.member` fineTriangles) . S.fromList) pieces) (Left (MissingFinerTriangle t))
      pure [(a, (sa, fa)), (b, (sb, fb)), (c, (sc, fc))]
    finerAt t point = case [(i, s) | (i, s) <- fineSamples, norm (sampleMaterial s ^-^ point) <= samePoint] of
      [found] -> Right found
      [] -> Left (MissingFinerPoint t)
      _ -> Left (AmbiguousFinerPoint t)

midpoint :: V2 -> V2 -> V2
midpoint p q = 0.5 *^ (p ^+^ q)

-- | A pose's screen with its finer level from the finer solve its gallery
-- names for it, if 'sameFinerPose' shows that solve is the same pose, and
-- the keys its report carries about that solve: its id, how a page labels
-- it, and how far apart the two are, or why it does not count. Where it
-- does not count, the pose's finer level stays not measured.
withFinerSolve :: Text -> Text -> (Screen, MaterialMesh) -> (Screen, MaterialMesh) -> (Screen, [Pair])
withFinerSolve finerId label (finerScreen, finerMesh) (screen, mesh) = case sameFinerPose mesh finerMesh of
  Right same -> (screen {screenTurningFiner = Just (screenTurning finerScreen)}, keys ["apartPixels" .= finerApartPixels same])
  Left refusal -> (screen, keys ["refused" .= explain refusal])
  where
    keys more = ["finerSolve" .= object (["id" .= finerId, "label" .= label] ++ more)]

-- | A pose whose report waits for its finer level: its id, its screen on
-- its own mesh, its mesh, and its report given its final screen and the
-- keys about its finer solve ('withFinerSolve').
data Pending = Pending
  { pendingId :: !Text,
    pendingScreen :: !Screen,
    pendingMesh :: !MaterialMesh,
    pendingReport :: Screen -> [Pair] -> Value
  }

-- | Every pose's report, in order, each pose taking its finer level from
-- the run its gallery names as the same control one level finer: a pose's
-- id, that run's id, and the label a page gives it. A pose named in no pair
-- keeps its finer level not measured. Naming a run the gallery does not
-- have is refused, since that is a mistake in the gallery, not a finding.
finishReports :: [(Text, Text, Text)] -> [Pending] -> Either Text [Value]
finishReports pairs poses = do
  let missing = [name | (pose, finer, _) <- pairs, name <- [pose, finer], M.notMember name byId]
  unless (null missing) (Left ("the gallery names a finer solve for a run it does not have: " <> tshow missing))
  pure (map finish poses)
  where
    byId = M.fromList [(pendingId p, p) | p <- poses]
    finerOf = M.fromList [(pose, (finer, label)) | (pose, finer, label) <- pairs]
    finish pose = case M.lookup (pendingId pose) finerOf of
      Just (finer, label)
        | Just run <- M.lookup finer byId ->
            let (screen, keys) = withFinerSolve finer label (pendingScreen run, pendingMesh run) (pendingScreen pose, pendingMesh pose)
             in pendingReport pose screen keys
      _ -> pendingReport pose (pendingScreen pose) []
