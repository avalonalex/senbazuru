-- | A run written as a sequence file (PRDs\/02-language-semantics.md, §11):
-- the quarter fold against the fixture its author folded by hand, state by
-- state, as PRD 09's test 1 compares it; the blintz's six states; and the
-- rules every written frame keeps.
module Senbazuru.Sequence.WriteSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (Value (..), object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Senbazuru.Diagram.Layout (defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Fold.Load (decodeFoldFile, encodeFoldFile, loadFoldFile)
import Senbazuru.Fold.Query (assignmentAtRest)
import Senbazuru.Fold.Types
import Senbazuru.Geometry.Rigid (rotationAbout)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface (surfaceFromFolded, transformSurface)
import Senbazuru.Render.Camera (defaultView)
import Senbazuru.Render.Steps (stepPage)
import Senbazuru.Render.Svg (Page (..), defaultPage, renderSvg)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (SequenceError)
import Senbazuru.Sequence.Record (Run (..), WrittenState (..), writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Layers (..), Line (..), Move (..), Point (..), RefusalKind (..), Sense (..), Sequence)
import Senbazuru.Sequence.Write
import Test.FoldFiles (goldenFoldFile)
import Test.Golden (goldenText)
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

spec :: Spec
spec = describe "writing a run as a sequence file" $ do
  quarterSheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  blintzSheet <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let sheets = M.fromList [("examples/quarter-fold-steps.fold", quarterSheet), ("examples/blintz-base.fold", blintzSheet)]
      written :: Sequence -> Either SequenceError FoldFile
      written sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate >>= writeSequence noFileHeader
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

  -- PRD 09's E4 and E5: the blintz's file is the one checked in, exactly
  -- but for coordinates, within 1e-12. It is generated by senbazuru
  -- (examples/README.md); regenerate it by accepting the .actual file this
  -- writes on a mismatch, after reading the diff.
  it "is the checked-in blintz-sequence.fold, coordinates within 1e-12 (E4, E5)" $
    goldenFoldFile 1e-12 "examples/blintz-sequence.fold" blintzFile

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

  -- PRD 09's E6.
  it "reads back as the file it wrote (E6)" $ do
    bytes <- either (fail . show) pure (encodeFoldFile blintzFile)
    decodeFoldFile bytes `shouldBe` Right blintzFile

  it "says it is FOLD 1.2, made by senbazuru, a diagram, titled as the sequence is" $ do
    (fileSpec quarter, fileCreator quarter, fileClasses quarter, fileTitle quarter) `shouldBe` (Just 1.2, Just "senbazuru", ["diagrams"], Just "A square folded into quarters")
    authored <- right (checkSequence quarterFold >>= runSequence defaultRunSettings sheets . elaborate >>= writeSequence (FileHeader (Just "A. Folder") (Just "Two folds.")))
    (fileAuthor authored, fileDescription authored) `shouldBe` (Just "A. Folder", Just "Two folds.")
  where
    pad = \case
      [x, y] -> [x, y, 0]
      other -> other
    near a b = length a == length b && and (zipWith (\x y -> abs (x - y) <= 1e-12) a b)
    startingAt start = Run Nothing start [] [] [] Nothing Nothing
    isArray = \case
      Array _ -> True
      _ -> False
    quarterWith second = sequenceOf (header "A square folded into quarters" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) $ do
      _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
      _ <- step "quarter" "Fold the top half down in front, onto the bottom." second
      pure ()

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
