-- | Present the blintz, run as a sequence from @blintz.foldseq@, through the
-- ordinary SVG/FOLD/glTF boundaries. The runner owns motion and state
-- handoff; this module only chooses illustrations and a camera. Mountain
-- folds in the source fixture go below its original xy plane, so view its
-- underside to see the flaps.
--
-- The page is eleven poses a run does not write: a step writes one state, its
-- end, and the page also shows each turn halfway, drawn from the turn each
-- record carries ('blintzStates'). The study's hand-written recipe drew the
-- same page from its own turns until the run was shown equal to it (#493);
-- @test/golden/checked-blintz.svg@ is the guard that comparison was.
module BlintzGallery (writeBlintzGallery, blintzStates, blintzFile, blintzSvg) where

import Control.Monad (forM)
import Data.Aeson (Value, encode, object, (.=))
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FoldRelaxation (maxLengthError)
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Load (loadFoldFile, readSequenceText)
import Senbazuru.Fold.Types (FaceId (..), FoldFile (..), Frame (..), emptyFrame)
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (CheckedFlap, flapAt, flapCheck, flapMovingFaces)
import Senbazuru.Origami.HingeSweep (sweepIntervals)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (View (..), basisFrom)
import Senbazuru.Render.Gltf (ExportMode (..), renderSurfaceGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, escapeXml, renderSvg)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Record (MoveRecord, RouteEvidence (..), Run (..), recordAfter, recordCaption, recordEvidence)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

-- | Eleven poses: the open square, then each turn halfway and its end. The
-- common ends appear once on the page. The interval check covers the turns
-- between these illustrations too.
blintzStates :: Run -> Either Text [(Text, Surface V2)]
blintzStates run = do
  turns <- traverse turnOf (runRecords run)
  case zip3 [1 :: Int ..] (runRecords run) turns of
    [] -> Left "the blintz run made no turns"
    moves@((_, _, opening) : _) -> do
      start <- first explain (flapAt opening 0)
      states <- traverse statesFor moves
      pure (("Start with the open square", start) : concat states)
  where
    statesFor (i, record, turn) = do
      midway <- first explain (flapAt turn 0.5)
      pure [("Move " <> tshow i <> " · halfway", midway), (fromMaybe ("Move " <> tshow i) (recordCaption record), recordAfter record)]

-- | Each record's turn, which the page draws part-way through.
turnOf :: MoveRecord -> Either Text CheckedFlap
turnOf record = case recordEvidence record of
  SweptHinge turn -> Right turn
  _ -> Left "a blintz move that is not a turn about a hinge"

blintzFile :: [(Text, Surface V2)] -> FoldFile
blintzFile states =
  FoldFile
    (Just 1.2)
    (Just "senbazuru checked blintz sequence")
    Nothing
    (Just "Blintz base, then reopen one corner")
    Nothing
    ["diagrams"]
    emptyFrame
    [(materialFrame surface) {frameTitle = Just title} | (title, surface) <- states]

blintzSvg :: FoldFile -> Either Text Text
blintzSvg file = do
  basis <- maybe (Left "invalid blintz camera") Right (basisFrom (V3 (-1) 0 1) (V3 0 0 1))
  drawing <- first explain (stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) {gridColumns = 4} (View (Just basis) 0) True (otherFrames file))
  diagram <- maybe (Left "blintz sequence has no geometry") Right drawing
  pure (renderSvg defaultPage {pageWidth = 1120, pageHeight = 900, pageMargin = 30, pageBackground = Nothing, pageTitle = fileTitle file} diagram)

writeBlintzGallery :: FilePath -> IO ()
writeBlintzGallery destination = do
  let output = destination </> "checked-blintz"
  createDirectoryIfMissing True output
  sheet <- loadFoldFile "examples/blintz-base.fold" >>= checked . first explain
  source <- readSequenceText "blintz.foldseq" >>= checked . first explain
  run <- checked (first explain (parseSequence "blintz.foldseq" source >>= checkSequence >>= runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" sheet) . elaborate))
  states <- checked (blintzStates run)
  moves <- checked (traverse (\record -> (,) record <$> turnOf record) (runRecords run))
  let file = blintzFile states
  BL.writeFile (output </> "sequence.fold") (encode file)
  svg <- checked (blintzSvg file)
  TIO.writeFile (output </> "sequence.svg") svg
  models <- forM (zip [0 :: Int ..] states) $ \(i, (title, surface)) -> do
    let path = "state-" ++ show i ++ ".glb"
    bytes <- checked (first explain (renderSurfaceGlb defaultBudget VisiblePaper (Just title) surface))
    BS.writeFile (output </> path) bytes
    pure (object ["title" .= (tshow (i + 1) <> " · " <> title), "path" .= path])
  reports <- traverse stateReport states
  BL.writeFile (output </> "models.json") (encode models)
  BL.writeFile (output </> "checks.json") (encode (object ["moves" .= map moveReport moves, "states" .= reports]))
  -- Reuse the existing viewer's locally installed Three.js dependency. This
  -- keeps --flap and --blintz usable together without a second npm install.
  copyFile "study/gltf/viewer.html" (output </> "index.html")
  viewer <- TIO.readFile (output </> "index.html")
  TIO.writeFile (output </> "index.html") (T.replace "./node_modules/" "../checked-flap/node_modules/" viewer)
  template <- TIO.readFile "study/fold-material/blintz.html"
  let captions = T.concat ["<li>" <> escapeXml title <> "</li>" | (title, _) <- states]
  TIO.writeFile (destination </> "blintz.html") (T.replace "<!--STATES-->" captions template)
  putStrLn ("Wrote checked blintz SVG, FOLD, eleven GLBs and blintz.html to " ++ destination)

moveReport :: (MoveRecord, CheckedFlap) -> Value
moveReport (record, turn) = object ["title" .= recordCaption record, "intervals" .= sweepIntervals (flapCheck turn), "movingFaces" .= map unFaceId (flapMovingFaces turn)]

stateReport :: (Text, Surface V2) -> IO Value
stateReport (title, surface) = do
  (mesh, _) <- checked (first explain (refineSurface 0 surface))
  let frame = surfaceFrame surface
  pure (object ["title" .= title, "maxRelativeEdgeError" .= maxLengthError mesh, "angles" .= edgesFoldAngle frame, "faceOrders" .= faceOrders frame])

checked :: Either Text a -> IO a
checked = either (die . T.unpack) pure
