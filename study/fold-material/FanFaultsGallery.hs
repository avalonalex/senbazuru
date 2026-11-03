-- | The fan-faults study (S9 of #637): every fault "FanFaults" measures, on the
-- fixtures #637 names, at the scales real pages draw them, written as JSON and
-- as the tables @docs/notes/fan-faults.md@ quotes.
--
-- The scales come from the library, never from a number typed here: the
-- uncaptioned page of steps (@render --steps@) for one to ten rows of three
-- figures of a unit sheet, through 'gridOf' and 'pageTransform', and the
-- captioned @run@ page through 'fitPage'. Only the first shrinks as rows are
-- added, since a captioned page at its default height grows taller instead
-- (owner decision 7), so each size is named by the pages that draw it.
--
-- The fixtures are the folded crane, the runs of @helmet.foldseq@ and
-- @blintz.foldseq@, and the flat states of @examples/bird-base-sequence.fold@.
-- A run's state drawn as a crease pattern is drawn unfanned, and so is left
-- out; so are the bird's states with paper in the air.
module FanFaultsGallery (writeFanFaults) where

import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as M
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import FanFaults
import Numeric (showFFloat)
import Senbazuru.Diagram (Diagram, diagramWithExtent)
import Senbazuru.Diagram.Layout (defaultGrid, gridOf)
import Senbazuru.Diagram.Page (FittedPage (..), Height (..), fitPage, pageTransform)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Explain (Explain, explain)
import Senbazuru.Fold.Load (decodeFoldFile, loadFoldFile, readSequenceText)
import Senbazuru.Fold.Query (Face (..), FrameKind (..), frameKind, frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), Transform (..), V2 (..))
import Senbazuru.Origami.Flat (flatSheet)
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Stacking (solveStacking)
import Senbazuru.Origami.Visible (EdgeSpan (..))
import Senbazuru.Render.Camera (Basis, bottomUp, isometric, topDown, turnedBy)
import Senbazuru.Render.Svg (defaultPage)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import System.Directory (createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))

-- | Measure every fixture and write @fan-faults.json@ and @fan-faults.md@
-- under the destination; the tables are printed too.
writeFanFaults :: FilePath -> IO ()
writeFanFaults destination = do
  createDirectoryIfMissing True destination
  steps <- said (traverse stepsScale [1 .. 10])
  runs <- said (traverse runScale [1 .. 10])
  crane <- loadCrane
  helmet <- runOf "examples/helmet-base.fold" "helmet.foldseq"
  blintz <- runOf "examples/blintz-base.fold" "blintz.foldseq"
  bird <- loadFoldFile "examples/bird-base-sequence.fold" >>= checked
  let scales = nub (map snd steps)
      birdFlat = [("state " <> tshow i, fr) | (i, fr) <- zip [0 :: Int ..] (otherFrames bird), isFlat fr]
      cases =
        [ Case "crane" "from above" topDown [("folded", crane)] [],
          Case "crane" "from below" bottomUp [("folded", crane)] [],
          Case "crane" "from above, turned 180°" (turnedBy pi topDown) [("folded", crane)] [],
          runCase "helmet" "from above" topDown helmet,
          runCase "helmet" "from below" bottomUp helmet,
          runCase "blintz" "from above" topDown blintz,
          runCase "blintz" "from below" bottomUp blintz,
          Case "bird base" "from above" topDown birdFlat [],
          Case "bird base" "from below" bottomUp birdFlat [],
          Case "bird base" "isometric, as its page" isometric birdFlat []
        ]
  results <- said (traverse (measure scales) cases)
  let tables = markdown steps runs results
  BL.writeFile (destination </> "fan-faults.json") (encode (report steps runs results))
  TIO.writeFile (destination </> "fan-faults.md") tables
  TIO.putStr tables
  putStrLn ("Wrote " <> (destination </> "fan-faults.json") <> " and fan-faults.md")

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure

-- | The same for a refusal already put into words.
said :: Either Text a -> IO a
said = either (die . T.unpack) pure

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- | Two decimals, which is finer than any stroke on the page.
num :: Double -> Text
num x = T.pack (showFFloat (Just 2) (if x == 0 then 0 else x) "")

-- * The pages

-- | A figure of a unit sheet: every fixture's sheet is a unit square, and a
-- page of steps draws every figure in one box, which the flat sheet sets when
-- it is the largest of them.
sheetFigure :: Diagram
sheetFigure = diagramWithExtent (Box (V2 0 0) (V2 1 1)) []

-- | Page units per model unit on the uncaptioned page of steps, @render
-- --steps@'s, with this many rows of three figures on the default page.
stepsScale :: Int -> Either Text (Int, Double)
stepsScale rows = case gridOf (defaultGrid defaultTheme) (replicate (3 * rows) sheetFigure) of
  Nothing -> Left ("no page of " <> tshow rows <> " rows")
  Just page -> let V2 s _ = tScale (pageTransform defaultPage page) in Right (rows, s)

-- | The same on a captioned @run@ page at its default height, which grows as
-- tall as its rows need.
runScale :: Int -> Either Text (Int, Double)
runScale rows = case fitPage defaultTheme (defaultGrid defaultTheme) HeightToFit defaultPage (replicate (3 * rows) (sheetFigure, Just "A step.")) of
  Left err -> Left (explain err)
  Right Nothing -> Left ("no page of " <> tshow rows <> " rows")
  Right (Just fitted) -> let V2 s _ = tScale (pageTransform (fittedPage fitted) (fittedDiagram fitted)) in Right (rows, s)

-- * The fixtures

-- | The crane folded along its own angles, its layers solved, as
-- @VisibleSpec@ folds it: the first stacking the solver finds.
loadCrane :: IO Frame
loadCrane = do
  bytes <- BS.readFile "test/fixtures/crane.fold"
  file <- either (die . ("crane: " <>)) pure (decodeFoldFile bytes)
  folded <- checked (foldFrame (keyFrame file))
  orders <- checked (solveStacking folded)
  pure folded {faceOrders = orders}

-- | A source run on its sheet, with the states it writes.
runOf :: FilePath -> FilePath -> IO (Run, [WrittenState])
runOf sheetPath sourcePath = do
  sheet <- loadFoldFile sheetPath >>= checked
  source <- readSequenceText sourcePath >>= checked
  run <- checked (parseSequence sourcePath source >>= checkSequence >>= runSequence defaultRunSettings (M.singleton sheetPath sheet) . elaborate)
  states <- checked (writtenStates run)
  pure (run, states)

-- | Flat as 'flatSheet' judges it, which is what fanning asks.
isFlat :: Frame -> Bool
isFlat = either (const False) (const True) . flatSheet

-- | Whether a page draws the frame as a folded form, the only kind it fans. A
-- crease pattern is drawn in crease-pattern notation, unfanned.
drawnFolded :: Frame -> Bool
drawnFolded fr = case frameVertices fr of
  Right verts -> frameKind (frameClasses fr) verts == FoldedForm
  Left _ -> False

-- | One fixture seen through one camera: the figures fanned, and the folds
-- whose hinges are measured on the figure before them.
data Case = Case
  { caseFixture :: !Text,
    caseView :: !Text,
    caseBasis :: !Basis,
    caseFigures :: ![(Text, Frame)],
    caseHinges :: ![Hinge]
  }

-- | A fold, its hinge edges, and the figure drawn before it: 'Nothing' where
-- that figure is drawn unfanned.
data Hinge = Hinge
  { hingeLabel :: !Text,
    hingeBefore :: !(Maybe Frame),
    hingeEdges :: ![EdgeId]
  }

-- | A run's fanned states, and its folds: every turn that is not an unfold,
-- which owner decision 74 draws no fold-here line for, and every pre-crease.
-- Each step of these runs makes one move, so the figure before a fold is the
-- state written before its step, and the fold is measured where its own record
-- holds the paper before it.
runCase :: Text -> Text -> Basis -> (Run, [WrittenState]) -> Case
runCase name view basis (run, states) = Case name view basis figures hinges
  where
    figures = [("state " <> tshow i, stateFrame st) | (i, st) <- zip [0 :: Int ..] states, drawnFolded (stateFrame st)]
    hinges = [Hinge (label r) (before r) (concatMap snd (recordHinge r)) | r <- runRecords run, folds r]
    folds r = case recordKind r of
      Turn -> not (recordUnfolds r)
      Precrease -> True
      _ -> False
    before r = case drop (recordStep r - 1) states of
      st : _ | drawnFolded (stateFrame st) -> Just (displayedFrame (recordBefore r) (displayBefore r))
      _ -> Nothing
    label r = "step " <> tshow (recordStep r)

-- * Measuring

data Measured = Measured
  { measuredCase :: !Case,
    measuredFigures :: ![FigureResult],
    measuredHinges :: ![(Text, Maybe [HingeMove])]
  }

data FigureResult = FigureResult
  { resultLabel :: !Text,
    resultFaces :: !Int,
    -- | At each scale, the faces whose fanned ring is not kept.
    resultShapes :: ![(Double, [(FaceId, FaceShape)])],
    resultBelow :: ![(FaceId, Double)],
    -- | At each scale, the ends that come apart from the paper they met.
    resultGaps :: ![(Double, [(MetEnd, Double)])],
    -- | Every end where a stretch's edge runs on under a nearer face.
    resultEnds :: ![MetEnd],
    resultMoved :: ![MovedPaper],
    resultBorderFolds :: ![BorderFold],
    resultAlongBorder :: !([EdgeId], Int)
  }

measure :: [Double] -> Case -> Either Text Measured
measure scales c = do
  figures <- traverse (\(label, fr) -> one label <$> figureOf (caseBasis c) fr) (caseFigures c)
  hinges <- traverse hinge (caseHinges c)
  pure (Measured c figures hinges)
  where
    one label fig =
      FigureResult
        { resultLabel = label,
          resultFaces = length (figureFaces fig),
          resultShapes = [(s, [(faceId face, shape) | face <- figureFaces fig, let shape = faceShapeAt fig s face, shape /= Kept]) | s <- scales],
          resultBelow = sortOn (Down . snd) [(faceId face, s) | face <- figureFaces fig, Just s <- [insideOutBelow fig face]],
          resultGaps = [(s, [(end, g) | end <- ends, let g = gapAt fig s end, g > noticeable]) | s <- scales],
          resultEnds = ends,
          resultMoved = movedPaper fig,
          resultBorderFolds = borderDrawnFolds fig,
          resultAlongBorder = foldsAlongBorder fig
        }
      where
        ends = metEnds fig
    hinge h = case hingeBefore h of
      Nothing -> Right (hingeLabel h, Nothing)
      Just fr -> (\fig -> (hingeLabel h, Just (hingeMoves fig (hingeEdges h)))) <$> figureOf (caseBasis c) fr

-- * The tables

markdown :: [(Int, Double)] -> [(Int, Double)] -> [Measured] -> Text
markdown steps runs results =
  T.unlines
    ( [ "## Faults by fixture and figure size",
        "",
        "Each cell is faces drawn inside out · faces crossing themselves · stretch ends that come apart from the paper they met, summed over the fixture's fanned figures. The sizes are page units per sheet length, on `render --steps`' uncaptioned page of three columns, by its rows: "
          <> T.intercalate "; " [num s <> " (" <> rowsText rs <> ")" | (s, rs) <- byScale]
          <> ". A captioned `run` page at its default height draws at "
          <> T.intercalate ", " (nub [num s | (_, s) <- runs])
          <> " whatever its rows.",
        "",
        "| Fixture | Seen | " <> T.intercalate " | " [num s | (s, _) <- byScale] <> " | Inside out below |",
        "| --- | --- | " <> T.intercalate " | " ["---:" | _ <- byScale] <> " | ---: |"
      ]
        <> [ "| " <> caseFixture (measuredCase m) <> " | " <> caseView (measuredCase m) <> " | " <> T.intercalate " | " [cell m s | (s, _) <- byScale] <> " | " <> largestBelow m <> " |"
             | m <- results
           ]
        <> [ "",
             "## Faults by fixture",
             "",
             "Visible paper moved is the faces whose visible boundary moves, how many of them lean, and the largest move. Folds drawn as a border are stretches drawn at border weight whose named edge is a fold, and the largest gap between the fold's move and its border's. Folds along a border are folds lying wholly along a border edge, drawn or not, out of all mountain and valley folds, in the state with most. A hinge move is the largest move of an end of a fold's hinge edges on the figure before the fold, drawn and buried, and in brackets its part square to the hinge. All in page units.",
             "",
             "| Fixture | Seen | Visible paper moved | Folds drawn as a border | Folds along a border | Hinge moves |",
             "| --- | --- | --- | --- | --- | --- |"
           ]
        <> [ "| " <> caseFixture (measuredCase m) <> " | " <> caseView (measuredCase m) <> " | " <> moved m <> " | " <> borderDrawn m <> " | " <> along m <> " | " <> hinges m <> " |"
             | m <- results
           ]
        <> [ "",
             "## Scales below which each face is drawn inside out",
             ""
           ]
        <> [ "- " <> caseFixture (measuredCase m) <> ", " <> caseView (measuredCase m) <> ": " <> T.intercalate "; " below
             | m <- results,
               let below = [resultLabel r <> " face " <> tshow (unFaceId f) <> " below " <> num s | r <- measuredFigures m, (f, s) <- resultBelow r, s >= 10],
               not (null below)
           ]
    )
  where
    byScale = [(s, [r | (r, s') <- steps, s' == s]) | s <- nub (map snd steps)]
    rowsText rs = case rs of
      [r] -> tshow r <> if r == 1 then " row" else " rows"
      _ -> tshow (minimum rs) <> "–" <> tshow (maximum rs) <> " rows"
    cell m s =
      let shapes = concat [fs | r <- measuredFigures m, (s', fs) <- resultShapes r, s' == s]
          gaps = concat [gs | r <- measuredFigures m, (s', gs) <- resultGaps r, s' == s]
          inside = length [() | (_, InsideOut) <- shapes]
          crossing = length [() | (_, shape) <- shapes, shape `elem` [CrossesItself, Collapsed]]
       in if inside + crossing + length gaps == 0 then "—" else tshow inside <> " · " <> tshow crossing <> " · " <> tshow (length gaps)
    largestBelow m = case [s | r <- measuredFigures m, (_, s) <- resultBelow r] of
      [] -> "—"
      ss -> num (maximum ss)
    moved m = case concatMap resultMoved (measuredFigures m) of
      [] -> "—"
      ps -> tshow (length ps) <> " faces, " <> tshow (length [() | p <- ps, movedMost p - movedLeast p > noticeable]) <> " leaning, up to " <> num (maximum (map movedMost ps))
    borderDrawn m = case concatMap resultBorderFolds (measuredFigures m) of
      [] -> "—"
      bs -> tshow (length bs) <> " stretches of " <> tshow (length (nub [(resultLabel r, spanFrom (borderFoldSpan b), spanTo (borderFoldSpan b)) | r <- measuredFigures m, b <- resultBorderFolds r])) <> " folds, up to " <> num (maximum (map borderFoldMismatch bs))
    along m = case sortOn (\(ids, n) -> (Down (length ids), Down n)) (map resultAlongBorder (measuredFigures m)) of
      (ids, n) : _ -> tshow (length ids) <> " of " <> tshow n
      [] -> "—"
    hinges m = case measuredHinges m of
      [] -> "—"
      hs -> T.intercalate "; " [label <> ": " <> hingeText moves | (label, moves) <- hs]
    hingeText moves = case moves of
      Nothing -> "drawn unfanned"
      Just ms -> T.intercalate ", " [kind <> " " <> most hs' | (kind, hs') <- [("drawn", filter hingeVisible ms), ("buried", filter (not . hingeVisible) ms)], not (null hs')]
    most hs' = case maximum (map hingeMost hs') of
      0 -> "0"
      m -> num m <> " (" <> num (maximum (map hingeSquare hs')) <> ")"

-- * The JSON

report :: [(Int, Double)] -> [(Int, Double)] -> [Measured] -> Value
report steps runs results =
  object
    [ "fanStep" .= fanStep,
      "fanCap" .= fanCap,
      "stepsPageScales" .= [object ["rows" .= r, "scale" .= s] | (r, s) <- steps],
      "runPageScales" .= [object ["rows" .= r, "scale" .= s] | (r, s) <- runs],
      "cases" .= map caseJson results
    ]
  where
    caseJson m =
      object
        [ "fixture" .= caseFixture (measuredCase m),
          "seen" .= caseView (measuredCase m),
          "figures" .= map figureJson (measuredFigures m),
          "hinges" .= [object ["fold" .= label, "moves" .= fmap (map hingeJson) moves] | (label, moves) <- measuredHinges m]
        ]
    figureJson r =
      object
        [ "figure" .= resultLabel r,
          "faces" .= resultFaces r,
          "metEnds" .= [object ["sheet" .= unFaceId (metSheet e), "covers" .= map unFaceId (metCovers e), "edge" .= edgeOf (metSpan e), "fraction" .= metFraction e] | e <- resultEnds r],
          "insideOutBelow" .= [object ["face" .= unFaceId f, "scale" .= s] | (f, s) <- resultBelow r],
          "atScale"
            .= [ object
                   [ "scale" .= s,
                     "insideOut" .= [unFaceId f | (f, InsideOut) <- shapes],
                     "crossesItself" .= [unFaceId f | (f, CrossesItself) <- shapes],
                     "collapsed" .= [unFaceId f | (f, Collapsed) <- shapes],
                     "gaps" .= [object ["sheet" .= unFaceId (metSheet e), "covers" .= map unFaceId (metCovers e), "edge" .= edgeOf (metSpan e), "fraction" .= metFraction e, "gap" .= g] | (e, g) <- gaps]
                   ]
                 | ((s, shapes), (_, gaps)) <- zip (resultShapes r) (resultGaps r)
               ],
          "movedPaper" .= [object ["face" .= unFaceId (movedFace p), "most" .= movedMost p, "least" .= movedLeast p] | p <- resultMoved r],
          "foldsDrawnAsBorder" .= [object ["sheet" .= fmap unFaceId (borderFoldSheet b), "edge" .= edgeOf (borderFoldSpan b), "mismatch" .= borderFoldMismatch b] | b <- resultBorderFolds r],
          "foldsAlongBorder" .= object ["edges" .= map unEdgeId (fst (resultAlongBorder r)), "folds" .= snd (resultAlongBorder r)]
        ]
    edgeOf sp = [unVertexId (spanFrom sp), unVertexId (spanTo sp)]
    hingeJson hm = object ["edge" .= unEdgeId (hingeEdge hm), "visible" .= hingeVisible hm, "most" .= hingeMost hm, "square" .= hingeSquare hm]
