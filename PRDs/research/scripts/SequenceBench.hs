-- Research driver for PRDs/research/gap-sequence-cost-and-test-budget.md, task (b).
-- NEVER BUILT OR RUN: it is kept because that note describes its method. It is
-- not part of the package; to try it, copy it to bench/Bench.hs in a scratch
-- clone and add this stanza to senbazuru.cabal:
--
--   executable senbazuru-bench
--     import:         warnings
--     hs-source-dirs: bench, study/fold-material
--     main-is:        Bench.hs
--     other-modules:  BlintzSequence, HelmetSequence, CraneWing, CheckedBird, CheckedPetal, PetalCertificate, StudyCase, ContactSpec, FoldMaterial
--     ghc-options:    -rtsopts
--     build-depends:  aeson, base, bytestring, containers, senbazuru, text
--
{-# OPTIONS_GHC -O0 #-}

-- | Scratch timing driver (not part of the repository). Main is compiled at
-- -O0 so the demand analyser cannot evaluate a timed argument before its
-- clock starts; every library module keeps the package's normal -O1.
module Main (main) where

import BlintzSequence (BlintzMove (..), buildBlintzSequence)
import CheckedBird (birdChecks, prepareBird)
import CheckedPetal (preparePetal)
import Control.Exception (evaluate)
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy qualified as BL
import StudyCase (CaseSpec (..), buildCaseSequence)
import Control.Monad (forM_, unless)
import CraneWing (CraneWing (..), buildCraneWing, craneFile, craneStates)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find, partition, sort)
import Data.Text (Text)
import Data.Text qualified as T
import GHC.Clock (getMonotonicTime)
import HelmetSequence (HelmetMove (..), buildHelmetSequence)
import Senbazuru.Diagram.Layout (defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Creasing (creaseAllAlong)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipSegment)
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Flat (Panel (..), Sheet (..), flatSheet)
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (SweepCheck (..), defaultSweepSettings)
import Senbazuru.Origami.Stacking (defaultBudget, solveStackingAs)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..))
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (defaultPage, renderSvg)
import System.CPUTime (getCPUTime)
import System.Environment (getArgs)
import System.Exit (die)
import Text.Printf (printf)

-- | Force a pure result completely (through 'show'), report wall and CPU time,
-- then show it again to measure the cost of forcing alone.
measure :: (Show a) => String -> (() -> a) -> IO a
measure label thunk = do
  w0 <- getMonotonicTime
  c0 <- getCPUTime
  let value = thunk ()
  n <- evaluate (length (show value))
  w1 <- getMonotonicTime
  c1 <- getCPUTime
  _ <- evaluate (length (show value))
  w2 <- getMonotonicTime
  printf "%-46s wall %10.3f ms  cpu %10.3f ms  show-only %8.3f ms  (%d chars)\n" label ((w1 - w0) * 1000) (fromIntegral (c1 - c0) / 1e9 :: Double) ((w2 - w1) * 1000) n
  pure value

timed :: (Show e, Show a) => String -> (() -> Either e a) -> IO a
timed label thunk = measure label thunk >>= either (die . ((label ++ ": ") ++) . show) pure

main :: IO ()
main = do
  args <- getArgs
  let pairs = case args of
        n : _ -> read n
        [] -> 10 :: Int
      skipSmall = "crane-only" `elem` args
  unless skipSmall $ do
    blintz <- loadFoldFile "examples/blintz-base.fold" >>= either (die . show) pure
    moves <- timed "blintz: buildBlintzSequence (5 steps)" (\() -> buildBlintzSequence (keyFrame blintz))
    printf "blintz intervals per move: %s\n" (show (map (sweepIntervals . flapCheck . blintzMotion) moves))
    helmet <- loadFoldFile "examples/helmet-base.fold" >>= either (die . show) pure
    hmoves <- timed "helmet: buildHelmetSequence (3 steps)" (\() -> buildHelmetSequence (keyFrame helmet))
    printf "helmet intervals per move: %s\n" (show (map (sweepIntervals . flapCheck . helmetMotion) hmoves))
    cases <- BL.readFile "study/fold-material/cases.json" >>= either die pure . eitherDecode
    entry <- maybe (die "missing bird case") pure (find ((== "bird-petal") . caseId) (cases :: [CaseSpec]))
    birdSource <- loadFoldFile (caseSource entry) >>= either (die . show) pure
    _ <- timed "bird: preparePetal" (\() -> preparePetal entry (keyFrame birdSource))
    bird <- timed "bird: prepareBird (4 stages)" (\() -> prepareBird entry (keyFrame birdSource))
    printf "bird certificates: %s\n" (show (birdChecks bird))
    _ <- timed "bird: buildCaseSequence" (\() -> buildCaseSequence entry birdSource)

  crane <- loadFoldFile "examples/crane.fold" >>= either (die . show) pure
  let source = keyFrame crane
  _ <- timed "crane: withPlanarFaces (faces recorded)" (\() -> withPlanarFaces source)
  original <- timed "crane: foldFrameWith source" (\() -> foldFrameWith source)
  let material = foldedPattern original
  _ <- timed "crane: withPlanarFaces (faces dropped)" (\() -> withPlanarFaces material {facesVertices = []})
  anchor <- case facesVertices material of
    ring : _ -> pure ring
    [] -> die "no faces"
  segments <- timed "crane: wingSegments (flatSheet+clip)" (\() -> wingSegments original)
  creased <- timed "crane: creaseAllAlong (4 segments)" (\() -> creaseAllAlong segments material)
  let (anchors, rest) = partition ((== sort anchor) . sort) (facesVertices creased)
  folded <- timed "crane: foldFrameWith creased" (\() -> foldFrameWith creased {facesVertices = anchors ++ rest})
  let frame = foldedFrame folded
      hinge = [EdgeId i | (i, assignment) <- zip [0 ..] (edgesAssignment frame), assignment == Unassigned]
  orders <- timed "crane: solveStackingAs [2]" (\() -> solveStackingAs defaultBudget [2] frame)
  let start = folded {foldedFrame = frame {faceOrders = orders}}
  wing <- timed "crane: buildCraneWing (whole recipe)" (\() -> buildCraneWing source)
  unless (craneHinge wing == hinge) (die "hinge differs from recipe")
  (mesh, _) <- either (die . show) pure (surfaceFromFolded start >>= refineSurface 0)
  printf "crane: %d vertices, %d faces, %d triangles, %d triangle pairs, %d moving faces\n" (length (verticesCoords frame)) (length (facesVertices frame)) (length (triangles mesh)) (let t = length (triangles mesh) in t * (t - 1) `div` 2) (length (flapMovingFaces (craneOpening wing)))
  refused <- measure "crane: refused -90 prepare+check" (\() -> prepareFlapAlong hinge (craneSide wing) (-90) start >>= checkFlap defaultSweepSettings)
  case refused of
    Left (FlapEndpointOrder 0 _) -> pure ()
    other -> die ("unexpected refusal result: " ++ take 200 (show other))

  let schedule = take (2 * pairs) (cycle [90, -90])
  wall0 <- getMonotonicTime
  final <- runSteps (craneSide wing) hinge start (zip [1 :: Int ..] schedule)
  wall1 <- getMonotonicTime
  printf "crane: %d-step open/close sequence total wall %.3f ms\n" (length schedule) ((wall1 - wall0) * 1000)
  printf "crane: final angles equal start: %s\n" (show (edgesFoldAngle (foldedFrame final) == edgesFoldAngle (foldedFrame start)))

  states <- timed "crane: craneStates (4 flapAt)" (\() -> craneStates wing)
  _ <- timed "crane: stepPage+renderSvg (4 figures)" (\() -> fmap (fmap (T.length . renderSvg defaultPage)) (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) (View Nothing 0) False (allFrames (craneFile states))))
  lastState <- case reverse states of
    (_, s) : _ -> pure s
    [] -> die "no states"
  _ <- timed "crane: renderSurfaceGlb VisiblePaper (90deg)" (\() -> renderSurfaceGlb defaultBudget VisiblePaper Nothing lastState)
  firstState <- case states of
    (_, s) : _ -> pure s
    [] -> die "no states"
  _ <- timed "crane: renderSurfaceGlb VisiblePaper (flat)" (\() -> renderSurfaceGlb defaultBudget VisiblePaper Nothing firstState)
  pure ()

runSteps :: FaceId -> [EdgeId] -> Folded -> [(Int, Double)] -> IO Folded
runSteps _ _ start [] = pure start
runSteps side hinge start ((i, travel) : rest) = do
  let label what = printf "step %02d (%+4.0f): %s" i travel (what :: String)
  motion <- timed (label "prepareFlapAlong") (\() -> prepareFlapAlong hinge side travel start)
  checked <- timed (label "checkFlap") (\() -> checkFlap defaultSweepSettings motion)
  end <- timed (label "flapAt 1") (\() -> flapAt checked 1)
  let accepted = surfaceFrame end
      nextPattern = (foldedPattern start) {edgesFoldAngle = edgesFoldAngle accepted, faceOrders = faceOrders accepted, frameExtras = mempty}
  next <- timed (label "join foldFrameWith") (\() -> foldFrameWith nextPattern)
  _ <- timed (label "join compare") (\() -> joinCheck accepted next nextPattern)
  printf "step %02d: intervals %d, orders %d\n" i (sweepIntervals (flapCheck checked)) (length (faceOrders accepted))
  runSteps side hinge next rest

joinCheck :: Frame -> Folded -> Frame -> Either Text Bool
joinCheck accepted next nextPattern = do
  expected <- first explain (frameVertices accepted)
  actual <- first explain (frameVertices (foldedFrame next))
  materialPoints <- first explain (frameVertices nextPattern)
  let scale = modelSpan materialPoints
  unless (length expected == length actual && and (zipWith (\a b -> norm (a ^-^ b) < 1e-12 * scale) expected actual)) $
    Left "refolding the accepted endpoint changed its position"
  pure True

-- Same selection as CraneWing's private wingSegments.
wingSegments :: Folded -> Either Text [(V2, V2, Assignment)]
wingSegments folded = do
  sheet <- first explain (flatSheet (foldedFrame folded))
  traverse (share sheet . FaceId) [2, 3, 6, 7]
  where
    share sheet fid = do
      panel <- maybe (Left "missing crane wing face") Right (find ((== fid) . panelId) (sheetPanels sheet))
      placement <- maybe (Left "missing crane wing placement") Right (IM.lookup (unFaceId fid) (foldedPlacements folded))
      (u, v) <- maybe (Left "wing crease missed a selected face") Right (clipSegment (panelRing panel) (V2 0 0.25, V2 2 0.25))
      let back (V2 x y) = case applyRigid (inverse placement) (V3 x y (sheetPlane sheet)) of
            V3 a b _ -> V2 a b
      pure (back u, back v, Unassigned)
