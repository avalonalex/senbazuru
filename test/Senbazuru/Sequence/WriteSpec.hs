-- | A run written as a sequence file (PRDs\/02-language-semantics.md, §11):
-- the quarter fold against the fixture its author folded by hand, state by
-- state, as PRD 09's test 1 compares it; the blintz's six states; a run from
-- a plain square whose crease graph grows, against D6's prefix rule; and the
-- rules every written frame keeps.
module Senbazuru.Sequence.WriteSpec (spec) where

import Control.Applicative ((<|>))
import Control.Monad (forM_)
import Data.Aeson (Result (..), Value (..), fromJSON, object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.Map.Strict qualified as M
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Senbazuru.Diagram.Layout (defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Fold.Load (decodeFoldFile, encodeFoldFile, loadFoldFile)
import Senbazuru.Fold.Query (assignmentAtRest)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.Rigid (identity, rotationAbout)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface (surfaceFromFolded, transformSurface)
import Senbazuru.Render.Camera (defaultView)
import Senbazuru.Render.Gltf (ExportMode (..), renderGlb)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Record (Run (..), WrittenState (..), recordNewCreases, recordStep, writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Layers (..), Line (..), Move (..), Point (..), RefusalKind (..), Sense (..), Sequence)
import Senbazuru.Sequence.Write
import Test.FoldFiles (goldenFoldFile)
import Test.Glb (Glb (..), parseGlb)
import Test.Glb qualified as Glb
import Test.Golden (goldenBytes, goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

spec :: Spec
spec = describe "writing a run as a sequence file" $ do
  quarterSheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  blintzSheet <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let sheets = M.fromList [("examples/quarter-fold-steps.fold", quarterSheet), ("examples/blintz-base.fold", blintzSheet)]
      ran :: Sequence -> Either SequenceError Run
      ran sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate
      written :: Sequence -> Either SequenceError FoldFile
      written sequence' = ran sequence' >>= writeSequence noFileHeader
      -- A run, and the states its file holds.
      grown = do
        run <- right (ran growing)
        file <- right (writeSequence noFileHeader run)
        pure (run, otherFrames file)
  quarter <- runIO (right (written quarterFold))
  blintzFile <- runIO (right (written blintz))

  -- PRD 09 §2.2. The fixture keeps its sheet in the key frame and its two
  -- folded states in file_frames; the written file keeps all three states in
  -- file_frames. So written state k is the fixture's key frame for k = 0 and
  -- its file_frames[k-1] after.
  describe "test 1: the quarter fold, state by state against its fixture" $ do
    let fixture = keyFrame quarterSheet : otherFrames quarterSheet
        states = otherFrames quarter

    it "has three states, and a key frame with no vertices" $ do
      length states `shouldBe` 3
      verticesCoords (keyFrame quarter) `shouldBe` []

    it "keeps the fixture's edges and faces, ids and ring order" $
      forM_ (zip states fixture) $ \(ours, theirs) -> do
        edgesVertices ours `shouldBe` edgesVertices theirs
        facesVertices ours `shouldBe` facesVertices theirs

    -- The fixture writes [x, y]; ours are [x, y, z] with z = 0, each within
    -- 1e-12 of the sheet's span, 1 here.
    it "places every vertex where the fixture does" $
      forM_ (zip states fixture) $ \(ours, theirs) ->
        and (zipWith near (verticesCoords ours) (map pad (verticesCoords theirs))) `shouldBe` True

    -- Exactly: a flap's end is the start angle plus a whole travel.
    it "writes the fixture's angles exactly" $
      map edgesFoldAngle states `shouldBe` map edgesFoldAngle fixture

    -- The fixture draws edges 8-11 M, V, M, M in every state, at angle 0
    -- too. Written by the state rule, a crease at 0 is F.
    it "letters each crease by its angle, not by what it will become" $ do
      map (drop 8 . edgesAssignment) states `shouldBe` [[Flat, Flat, Flat, Flat], [Mountain, Flat, Mountain, Flat], [Mountain, Valley, Mountain, Mountain]]
      forM_ (zip states fixture) $ \(ours, theirs) ->
        edgesAssignment ours `shouldBe` zipWith assignmentAtRest (edgesAssignment theirs) (edgesFoldAngle theirs)

    -- The fixture's key frame says frame_attributes ["2D"]; a state folded
    -- from it is no longer that sheet, and carries none of its frame keys.
    it "keeps none of the sheet's own frame metadata" $
      map (\frame -> (frameAttributes frame, frameAuthor frame, frameDescription frame)) states `shouldBe` replicate 3 ([], Nothing, Nothing)

    it "calls the flat sheet a crease pattern and the folded states folded forms" $
      map frameClasses states `shouldBe` [["creasePattern"], ["foldedForm"], ["foldedForm"]]

  -- PRD 02 §11's table: a state's title is the caption of the step leaving
  -- it, and the last is the closing; its assurance is the step that produced
  -- it, absent on state 0.
  describe "the quarter fold's captions and assurance" $ do
    it "titles each state with the step that leaves it, and the last with the closing" $
      map frameTitle (otherFrames quarter) `shouldBe` [Just "Fold the left half behind, onto the right.", Just "Fold the top half down in front, onto the bottom.", Just "Folded into quarters."]

    it "says what checked each state's step, and nothing for the sheet" $
      map (KM.lookup "senbazuru:assurance" . frameExtras) (otherFrames quarter)
        `shouldBe` [Nothing, Just (toJSON [object ["move" .= (1 :: Int), "evidence" .= ("SweptHinge" :: Text)]]), Just (toJSON [object ["move" .= (1 :: Int), "evidence" .= ("SweptHinge" :: Text)]])]

    it "carries each state's material coordinates" $
      map (fmap isArray . KM.lookup "senbazuru:material_coords" . frameExtras) (otherFrames quarter) `shouldBe` replicate 3 (Just True)

  -- PRD 09's E4 and E5: the blintz's file is the one checked in, coordinates
  -- and all. Every crease of it turns by 0° or ±180°, which folding computes
  -- from arithmetic and square roots alone ("Senbazuru.Geometry.Rigid"), and
  -- those round the same on every platform, so E5's tolerance of 1e-12 is not
  -- needed; CI checks the same file on Linux. Turns red if a flat turn took
  -- its sine from sin pi, 1.2e-16, as it did. It is generated by senbazuru
  -- (examples/README.md);
  -- regenerate it by accepting the .actual file this writes on a mismatch,
  -- after reading the diff.
  it "is the checked-in blintz-sequence.fold exactly, coordinates and all (E4, E5)" $
    goldenFoldFile 0 "examples/blintz-sequence.fold" blintzFile

  -- Test 1's page: the written file drawn as `render --steps` draws it. It
  -- cannot be quarter-fold-steps.svg, the fixture's page: the state rule
  -- writes the flat creases F, which draw grey and solid where the fixture's
  -- M and V at angle 0 draw dashed.
  it "draws test 1's page as render --steps draws the written file" $
    case stepPage defaultTheme defaultBudget (defaultGrid defaultTheme) defaultView True (allFrames quarter) of
      Right (Just page) -> goldenText "test/golden/quarter-fold-sequence-steps.svg" (renderSvg defaultPage {pageWidth = 400, pageHeight = 200, pageMargin = 10, pageTitle = Just "fixture"} page)
      other -> expectationFailure ("expected a page, got " <> either show (const "nothing to lay out") other)

  -- PRD 03's A-6: five steps, six states, made with no I/O.
  it "writes the blintz as six states, the start and one per step (A-6)" $
    length (otherFrames blintzFile) `shouldBe` 6

  -- PRD 09's M2 (f).
  it "gives every written frame its angles, no U, and no M or V at angle 0" $
    forM_ (otherFrames quarter ++ otherFrames blintzFile) $ \frame -> do
      length (edgesFoldAngle frame) `shouldBe` length (edgesVertices frame)
      Unassigned `elem` edgesAssignment frame `shouldBe` False
      [(letter, angle) | (letter, angle) <- zip (edgesAssignment frame) (edgesFoldAngle frame), letter `elem` [Mountain, Valley], angle == 0] `shouldBe` []
      [angle | (Flat, angle) <- zip (edgesAssignment frame) (edgesFoldAngle frame), angle /= 0] `shouldBe` []

  -- PRD 04's A18: stopped at step 2, the file holds the two states before
  -- it, and the last is titled with the step it stopped at.
  it "writes the states before a not modelled stop, and none for the stop (A18)" $ do
    stopped <- right (written (quarterWith (notModelled "fold in quarters")))
    length (otherFrames stopped) `shouldBe` 2
    map frameTitle (otherFrames stopped) `shouldBe` [Just "Fold the left half behind, onto the right.", Just "Fold the top half down in front, onto the bottom."]

  -- D24: a step of nothing but expect refused moved no paper and writes no
  -- state. A step that made no record still writes one, the same as before.
  describe "which steps write a state" $ do
    -- A line through two points says nothing of which side moves, and with
    -- no moving point it is always refused, as SeedMissing.
    it "not one whose moves were all expect refused" $ do
      file <- right (written (quarterWith (expectRefused (RefusalKind "SeedMissing") (Fold ValleyFold ToFlat (Segment (MidpointOfEdge South) (MidpointOfEdge North)) FlapOfFirstArgument Nothing))))
      length (otherFrames file) `shouldBe` 2

    it "but one that made no record, at the state before it" $ do
      file <-
        right
          ( written
              ( sequenceOf (header "Twice" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
                  c1 <- step "c1" "Fold a corner behind." (fold mountain (cornerOf SouthEast `onto` centre))
                  step_ "Open it." (unfold [c1])
                  step_ "Open it again, which does nothing." (unfold [c1])
              )
          )
      case otherFrames file of
        [_, _, opened, again] -> (verticesCoords again, edgesFoldAngle again) `shouldBe` (verticesCoords opened, edgesFoldAngle opened)
        frames -> expectationFailure ("expected four states, got " <> show (length frames))

  -- D6 (PRDs/decisions.md): a run's crease graph grows from one state to the
  -- next, and a state's vertex ids are the first ids of the next, each the
  -- same point of paper. That is the prefix rule, by which #638's
  -- motionsAcross, not built yet, will pair two states. It holds because
  -- cutting and creasing never renumber a vertex. This run creases a plain
  -- square at both steps: the diagonal from corner south-west to corner
  -- north-east, then the vertical midline, which cuts the south and north
  -- edges and crosses the diagonal at (1/2, 1/2). Its anchor is written so
  -- that neither step moves the anchor's paper, and the run never
  -- re-anchors. Built in beforeAll, as 09 §6.3 asks of a new run, so a
  -- refusal fails these items and no others.
  describe "a crease graph that grows, as D6's prefix rule needs" . beforeAll grown $ do
    -- Worked by hand, then run. The diagonal joins two corners the square
    -- has: one edge more, and two faces. The midline adds three vertices,
    -- cuts the south edge, the north edge and the diagonal in two, is two
    -- edges itself, and halves both faces. Turns red if a crease were
    -- written before the step that makes it, as backfilling the last crease
    -- graph into every state would (D6's rejected choice), or if the midline
    -- did not cut the diagonal.
    it "writes 4, 4, 1, then 4, 5, 2, then 7, 10, 4 vertices, edges and faces" $ \(_, states) ->
      map counts states `shouldBe` [(4, 4, 1), (4, 5, 2), (7, 10, 4)]

    -- Material coordinates only, exactly: positions move whenever paper
    -- turns, and the rule is about ids and paper, each kept vertex carried
    -- through as the same value. Turns red if creasing or the writer
    -- renumbered a vertex, as writing them in the order a fresh trace of the
    -- faces met them would, or if a state were written with an earlier
    -- state's material coordinates, one point short for each new vertex.
    -- Both need a pair that adds vertices, which the first line asks for
    -- here rather than leaving it to the counts above.
    it "keeps each state's vertices as the first of the next's, on the same paper" $ \(_, states) -> do
      [() | (earlier, later) <- pairs states, length (verticesCoords later) > length (verticesCoords earlier)] `shouldNotBe` []
      forM_ (pairs states) $ \(earlier, later) -> do
        was <- materialOf earlier
        now <- materialOf later
        (length was, length now) `shouldBe` (length (verticesCoords earlier), length (verticesCoords later))
        take (length was) now `shouldBe` was

    -- The counts above say each state has more edges than the one before;
    -- this says why, from the run's own records: both steps crease. Turns
    -- red if a move's record lost the creases its move drew, as a
    -- pre-crease's record would if 'asPrecrease' cleared them. The written
    -- states do not read the records' creases, so the counts stay green then.
    it "records new creases at both steps" $ \(run, _) ->
      [recordStep record | record <- runRecords run, not (null (recordNewCreases record))] `shouldBe` [1, 2]

  -- PRD 09 §2.3's test 2 is test 1 run from sheet square, with the same
  -- anchor and steps. Its second step creases folded paper, which waits for
  -- M4; its first runs now. The midline cuts the south and north edges and
  -- halves the square: 6 vertices and 7 edges, as 09 worked out on
  -- hand-built frames, and 2 faces; 09 now cites this test for all three.
  -- Turns red if a state were written from the paper as its step found it,
  -- an off-by-one between states and steps, which would write (4, 4, 1)
  -- twice.
  it "writes test 2's state 1 as 09 §2.3 counts it: 6 vertices, 7 edges, 2 faces" $ do
    file <- right (written testTwoFirstStep)
    map counts (otherFrames file) `shouldBe` [(4, 4, 1), (6, 7, 2)]

  -- Two of the rules no run reaches yet: every run so far ends its flat
  -- creases at exactly 0, and no move turns the sheet face down. So these
  -- hand writtenStates a start state made to need them.
  describe "the rules no run reaches yet" $ do
    -- A crease a hair off zero is flat by the rule, and is written at
    -- exactly 0, so that a reader testing angle /= 0 agrees with its F.
    it "writes a crease 5e-11 off zero as F at exactly 0" $ do
      laid <- right (sheetState blintzSheet)
      let paper = workingPattern laid
      nudged <- right (foldFrameWith paper {edgesFoldAngle = [if e == (8 :: Int) then 5e-11 else 0 | e <- zipWith const [0 ..] (edgesVertices paper)]})
      start <- right (surfaceFromFolded nudged)
      states <- right (writtenStates (startingAt start))
      [(edgesAssignment frame !! 8, edgesFoldAngle frame !! 8) | WrittenState _ frame <- states] `shouldBe` [(Flat, 0)]

    -- Every angle 0, and every face showing its back: flat, but not the
    -- pattern as drawn.
    it "calls a flat sheet turned face down a folded form" $ do
      laid <- right (sheetState blintzSheet)
      folded <- right (foldFrameWith (workingPattern laid))
      start <- right (surfaceFromFolded folded)
      turned <- right (transformSurface (rotationAbout (V3 0.5 0.5 0) (V3 1 0 0) pi) start)
      states <- right (writtenStates (startingAt turned))
      map (frameClasses . stateFrame) states `shouldBe` [["foldedForm"]]

  -- PRD 09's E8 and E9: the last state as a 3D model, as `run -o x.glb`
  -- writes it, through renderGlb with export's title rule. E8 pins its bytes;
  -- E9 reads back the frame the model carries and finds the written state:
  -- exact in topology, angles and orders, and positions within the model's
  -- rounding, 1e-6 of its span.
  describe "the last state as a model (E8, E9)" $ do
    final <- runIO (maybe (fail "no states") pure (lastOf (otherFrames blintzFile)))
    bytes <- runIO (either (fail . show) pure (renderGlb defaultBudget VisiblePaper (frameTitle final <|> fileTitle blintzFile) final))

    it "is the checked-in blintz-sequence-final.glb (E8)" $
      goldenBytes "test/golden/blintz-sequence-final.glb" bytes

    it "carries the state it was made from (E9)" $ do
      glb <- parseGlb bytes
      stored <- case fromJSON (Glb.at "frame" (Glb.at "senbazuru" (Glb.at "extras" (glbJson glb)))) of
        Success frame -> pure frame
        Error why -> fail why
      (edgesVertices stored, facesVertices stored, edgesFoldAngle stored, faceOrders stored)
        `shouldBe` (edgesVertices final, facesVertices final, edgesFoldAngle final, faceOrders final)
      and (zipWith (\a b -> abs (a - b) <= 1e-6) (concat (verticesCoords stored)) (concat (verticesCoords final))) `shouldBe` True
      map length (verticesCoords stored) `shouldBe` map length (verticesCoords final)

  -- PRD 09's E6.
  it "reads back as the file it wrote (E6)" $ do
    bytes <- either (fail . show) pure (encodeFoldFile blintzFile)
    decodeFoldFile bytes `shouldBe` Right blintzFile

  it "says it is FOLD 1.2, made by senbazuru, a diagram, titled as the sequence is" $ do
    (fileSpec quarter, fileCreator quarter, fileClasses quarter, fileTitle quarter) `shouldBe` (Just 1.2, Just "senbazuru", ["diagrams"], Just "A square folded into quarters")
    authored <- right (ran quarterFold >>= writeSequence (FileHeader (Just "A. Folder") (Just "Two folds.")))
    (fileAuthor authored, fileDescription authored) `shouldBe` (Just "A. Folder", Just "Two folds.")
  where
    pad = \case
      [x, y] -> [x, y, 0]
      other -> other
    near a b = length a == length b && and (zipWith (\x y -> abs (x - y) <= 1e-12) a b)
    startingAt start = Run Nothing start identity [] [] [] Nothing Nothing
    lastOf = listToMaybe . reverse
    isArray = \case
      Array _ -> True
      _ -> False
    quarterWith second = sequenceOf (header "A square folded into quarters" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) $ do
      _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      _ <- step "quarter" "Fold the top half down in front, onto the bottom." second
      pure ()
    -- A line through two points says nothing of which side moves, so the
    -- pre-crease names the paper it moves (otherwise SeedMissing).
    growing = sequenceOf (header "A square creased twice" sheetSquare (Just (at (3 / 4) (1 / 4)))) $ do
      step_ "Crease the diagonal from the bottom-left corner to the top-right." (move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf NorthWest))))
      step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
    pairs states = zip states (drop 1 states)
    testTwoFirstStep = sequenceOf (header "A square folded in half" sheetSquare (Just (at (3 / 4) (1 / 4)))) $ do
      _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      pure ()
    counts frame = (length (verticesCoords frame), length (edgesVertices frame), length (facesVertices frame))
    materialOf :: Frame -> IO [(Double, Double)]
    materialOf frame = case fromJSON <$> KM.lookup "senbazuru:material_coords" (frameExtras frame) of
      Just (Success points) -> pure points
      _ -> fail "a written state without two-coordinate material points"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
