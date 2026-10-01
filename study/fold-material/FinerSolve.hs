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
-- same /control/ (docs/glossary.md) on the finer mesh anyway, to see whether
-- refining changes the answer. Decision 29 counts that solve as the pose made
-- again where it is shown to be the same pose:
--
-- 1. its mesh is the pose's mesh with every triangle split into four;
-- 2. it solves the same control;
-- 3. the two solves agree at every vertex of the coarser mesh within the
--    floor limit, 'floorLimitPixels' at the scale the page draws its poses
--    at (owner decision 30).
--
-- 'sameFinerPose' checks the first and the third, and of the second what a
-- mesh can show: that both solves hold the sheet at the same points, and
-- hold the coarser mesh's held vertices in the same places. The rest of a
-- control, its stiffness, contact order and settings, only the gallery
-- knows, so each gallery names its pairs. A finer solve its gallery does
-- not /accept/ (docs/glossary.md), for example one that did not converge,
-- does not count either (owner decision 31): the solve that stands for the
-- pose made again must be one the gallery stands behind.
--
-- What a newcomer would get wrong is matching the two meshes by vertex
-- number. The finer mesh numbers its vertices its own way; what the two
-- share is the flat sheet. So a coarse triangle's corners and edge midpoints
-- are looked up by /material point/, each of which must be exactly one
-- vertex of the finer mesh, and the finer mesh must hold the four triangles
-- each coarse triangle splits into and nothing else. Agreement is judged at
-- the coarser mesh's vertices only, as the decision says: between them the
-- coarser mesh is flat, so at a finer solve's edge midpoints the two can lie
-- further apart where the paper curves, up to 1.3 px on the wing gripped at
-- 40 degrees, whose vertices agree within 0.81 px.
module FinerSolve
  ( SameFinerPose (..),
    FinerSolveRefusal (..),
    samePoint,
    sameFinerPose,
    Pending (..),
    finerLevel,
    finishReports,
  )
where

import Control.Monad (forM, forM_, unless)
import Data.Aeson (Value, object, (.=))
import Data.Aeson.Types (Pair)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import PaperScreen (Turning, maximumOn)
import ScreenReport (PageScale (..), floorLimitPixels)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))

-- | A finer solve shown to be the same pose one level finer: how far apart
-- the two solves are at worst, over the coarser mesh's vertices, in pixels
-- at the page's scale.
newtype SameFinerPose = SameFinerPose {finerApartPixels :: Double}
  deriving stock (Eq, Show)

-- | Why a finer solve does not count as the pose made again, and where the
-- check stopped. A triangle or vertex is the coarser mesh's unless it is
-- said to be the finer mesh's, and a point is a point of the flat sheet.
data FinerSolveRefusal
  = -- | The finer mesh has the second number of triangles, where four for
    -- each of the coarser mesh's would be the first.
    FinerTriangleCount !Int !Int
  | -- | This triangle names this vertex, which its mesh does not have.
    UnknownCoarseVertex !Int !Int
  | -- | No vertex of the finer mesh lies at this point, a corner or edge
    -- midpoint of this triangle.
    MissingFinerPoint !Int !V2
  | -- | These vertices of the finer mesh all lie at one corner or edge
    -- midpoint of this triangle.
    AmbiguousFinerPoint !Int ![Int]
  | -- | The finer mesh lacks this triangle, given by its own vertices, one of
    -- the four this triangle splits into.
    MissingFinerTriangle !Int !(Int, Int, Int)
  | -- | At this point one solve holds the sheet and the other does not, or
    -- they hold it in different places.
    DifferentHolds !V2
  | -- | At this vertex the two solves are this many pixels apart, beyond the
    -- floor limit or no finite distance at all.
    SolvesApart !Int !Double
  | -- | The gallery does not accept the finer solve.
    FinerNotAccepted
  deriving stock (Eq, Show)

instance Explain FinerSolveRefusal where
  explain = \case
    FinerTriangleCount expected actual -> "the finer mesh has " <> tshow actual <> " triangles, not " <> tshow expected <> ", four for each of this mesh's, so it is not this mesh split into four"
    UnknownCoarseVertex t v -> "triangle " <> tshow t <> " names vertex " <> tshow v <> ", which its mesh does not have"
    MissingFinerPoint t p -> "no vertex of the finer mesh lies at " <> point p <> ", a corner or edge midpoint of triangle " <> tshow t <> ", so the finer mesh is not this mesh split into four"
    AmbiguousFinerPoint t vs -> "vertices " <> T.intercalate ", " (map tshow vs) <> " of the finer mesh all lie at one corner or edge midpoint of triangle " <> tshow t <> ", so the two meshes cannot be matched on the flat sheet"
    MissingFinerTriangle t (a, b, c) -> "the finer mesh has no triangle on its vertices " <> tshow a <> ", " <> tshow b <> " and " <> tshow c <> ", one of the four that triangle " <> tshow t <> " splits into, so it is not this mesh split into four"
    DifferentHolds p -> "at " <> point p <> " one solve holds the sheet and the other does not, or they hold it in different places, so they do not solve the same control"
    SolvesApart v pixels -> "at vertex " <> tshow v <> " of this mesh the two solves are " <> num pixels <> " px apart, not within the floor limit, so the finer solve may be another shape"
    FinerNotAccepted -> "the gallery does not accept the finer solve, whose own report says why, so it cannot stand for this pose made again"
    where
      point (V2 u v) = "(" <> num u <> ", " <> num v <> ") on the flat sheet"

-- | Two points of the flat sheet closer than this, in sheet units, are one
-- point: far below any mesh's spacing, and far above the rounding in a
-- midpoint worked out from its ends. Two held targets closer than this are
-- one place.
samePoint :: Double
samePoint = 1e-9

-- | Whether @fine@, holding the sheet at @fineHeld@, is the pose @coarse@,
-- holding it at @coarseHeld@, one level finer: its mesh split into four,
-- holding the same points, and the coarser mesh's held vertices in the same
-- places, and within the floor limit of it at every vertex, on a page drawn
-- at @scale@. The result is how far apart the two are at worst. A held map
-- gives each held vertex the position it is held at.
sameFinerPose :: PageScale -> IM.IntMap V3 -> MaterialMesh -> IM.IntMap V3 -> MaterialMesh -> Either FinerSolveRefusal SameFinerPose
sameFinerPose scale coarseHeld coarse fineHeld fine = do
  let expected = 4 * length (triangles coarse)
  unless (length (triangles fine) == expected) (Left (FinerTriangleCount expected (length (triangles fine))))
  matched <- concat <$> forM (zip [0 ..] (triangles coarse)) split
  -- A vertex shared by several coarse triangles is matched once for each;
  -- every match finds the same finer vertex, so keeping one loses nothing.
  let apart = [(v, pixelsPerSheet scale * norm (position c ^-^ position f)) | (v, (c, f)) <- IM.toList (IM.fromList matched)]
      -- A comparison with NaN is false whichever way it is asked, so a
      -- distance that is no number is refused by name, and the worst is
      -- found with NaN ranked above every number.
      worst = maximumOn (\(_, pixels) -> if isNaN pixels then 1 / 0 else pixels)
  case worst [(v, pixels) | (v, pixels) <- apart, isNaN pixels || pixels > floorLimitPixels] of
    Just (v, pixels) -> Left (SolvesApart v pixels)
    Nothing -> Right (SameFinerPose (maybe 0 snd (worst apart)))
  where
    coarseSamples = IM.fromList (zip [0 ..] (samples coarse))
    fineSamples = zip [0 :: Int ..] (samples fine)
    fineTriangles = S.fromList [S.fromList [a, b, c] | (a, b, c) <- triangles fine]
    -- One coarse triangle: its corners and edge midpoints as finer
    -- vertices, the four triangles it splits into among the finer mesh's,
    -- and the holds there. The result pairs each corner's coarse vertex
    -- with its coarse and finer samples.
    split (t, (a, b, c)) = do
      (sa, sb, sc) <- (,,) <$> coarseAt t a <*> coarseAt t b <*> coarseAt t c
      let (ma, mb, mc) = (sampleMaterial sa, sampleMaterial sb, sampleMaterial sc)
          (mab, mbc, mca) = (midpoint ma mb, midpoint mb mc, midpoint mc ma)
      (ia, fa) <- finerAt t ma
      (ib, fb) <- finerAt t mb
      (ic, fc) <- finerAt t mc
      (iab, _) <- finerAt t mab
      (ibc, _) <- finerAt t mbc
      (ica, _) <- finerAt t mca
      forM_ [(ia, iab, ica), (iab, ib, ibc), (ica, ibc, ic), (iab, ibc, ica)] $ \piece@(x, y, z) ->
        unless (S.fromList [x, y, z] `S.member` fineTriangles) (Left (MissingFinerTriangle t piece))
      -- A corner is held exactly when its finer vertex is, in the same
      -- place; an edge's midpoint exactly when both ends of the edge are.
      -- Where a midpoint is held is not compared: the coarser solve has no
      -- vertex there.
      forM_ [(ma, a, ia), (mb, b, ib), (mc, c, ic)] $ \(m, v, i) ->
        case (IM.lookup v coarseHeld, IM.lookup i fineHeld) of
          (Nothing, Nothing) -> pure ()
          (Just p, Just q) | norm (p ^-^ q) <= samePoint -> pure ()
          _ -> Left (DifferentHolds m)
      forM_ [(mab, a, b, iab), (mbc, b, c, ibc), (mca, c, a, ica)] $ \(m, v, w, i) ->
        unless ((IM.member v coarseHeld && IM.member w coarseHeld) == IM.member i fineHeld) (Left (DifferentHolds m))
      pure [(a, (sa, fa)), (b, (sb, fb)), (c, (sc, fc))]
    coarseAt t v = maybe (Left (UnknownCoarseVertex t v)) Right (IM.lookup v coarseSamples)
    finerAt t p = case [(i, s) | (i, s) <- fineSamples, norm (sampleMaterial s ^-^ p) <= samePoint] of
      [found] -> Right found
      [] -> Left (MissingFinerPoint t p)
      several -> Left (AmbiguousFinerPoint t (map fst several))

midpoint :: V2 -> V2 -> V2
midpoint p q = 0.5 *^ (p ^+^ q)

-- | A pose as its gallery hands it over before its finer level and its
-- page's scale are settled: its id; whether the gallery accepts its solve;
-- the points the solve holds, each with the position it is held at; its
-- mesh; its own false-crease turning, which is the finer level it gives a
-- coarser pose; and its report, given the page's scale, its finer level and
-- the keys about its finer solve. The report screens the pose at that finer
-- level, so no screen made before it is settled can reach the report.
data Pending = Pending
  { pendingId :: !Text,
    pendingAccepted :: !Bool,
    pendingHeld :: !(IM.IntMap V3),
    pendingMesh :: !MaterialMesh,
    pendingTurning :: !Turning,
    pendingReport :: PageScale -> Maybe Turning -> [Pair] -> Either Text Value
  }

-- | A pose's finer level from the finer solve its gallery names for it, on
-- a page drawn at @scale@, and the keys its report carries about that
-- solve: its id, how a page labels it, whether the gallery accepts it, and
-- how far apart the two are, or why it does not count. The finer level is
-- the finer solve's own false-crease turning where its gallery accepts it
-- and 'sameFinerPose' shows the two are the same pose, and not measured
-- where either fails. Only the finer solve's acceptance is asked, never the
-- pose's: the screen judges every pose's shape whatever its gallery makes
-- of it, and only the solve that stands for the pose made again has to be
-- one its gallery stands behind.
finerLevel :: PageScale -> Text -> Pending -> Pending -> (Maybe Turning, [Pair])
finerLevel scale label finer pose = case counted of
  Right same -> (Just (pendingTurning finer), keys ["apartPixels" .= finerApartPixels same])
  Left refusal -> (Nothing, keys ["refused" .= explain refusal])
  where
    counted = do
      unless (pendingAccepted finer) (Left FinerNotAccepted)
      sameFinerPose scale (pendingHeld pose) (pendingMesh pose) (pendingHeld finer) (pendingMesh finer)
    keys more = ["finerSolve" .= object (["id" .= pendingId finer, "label" .= label, "accepted" .= pendingAccepted finer] ++ more)]

-- | Every pose's report, in order, on a page drawn at @scale@, each pose
-- taking its finer level from the run its gallery names as the same control
-- one level finer: a pose's id, that run's id, and the label a page gives
-- it. A pose named in no pair keeps its finer level not measured. A name the
-- gallery does not have, two runs with one id, or one pose named in two
-- pairs is refused, since each is a mistake in the gallery, not a finding.
finishReports :: PageScale -> [(Text, Text, Text)] -> [Pending] -> Either Text [Value]
finishReports scale pairs poses = do
  unless (null (repeated (map pendingId poses))) (Left ("the gallery has more than one run named " <> T.intercalate ", " (repeated (map pendingId poses))))
  unless (null (repeated named)) (Left ("the gallery names more than one finer solve for " <> T.intercalate ", " (repeated named)))
  finerOf <- M.fromList <$> traverse resolve pairs
  traverse (report finerOf) poses
  where
    named = [pose | (pose, _, _) <- pairs]
    byId = M.fromList [(pendingId p, p) | p <- poses]
    run name = maybe (Left ("the gallery names a finer solve for a run it does not have: " <> name)) Right (M.lookup name byId)
    resolve (pose, finer, label) = do
      _ <- run pose
      found <- run finer
      pure (pose, (found, label))
    report finerOf pose = case M.lookup (pendingId pose) finerOf of
      Just (finer, label) -> uncurry (pendingReport pose scale) (finerLevel scale label finer pose)
      Nothing -> pendingReport pose scale Nothing []
    repeated xs = M.keys (M.filter (> (1 :: Int)) (M.fromListWith (+) [(x, 1) | x <- xs]))
