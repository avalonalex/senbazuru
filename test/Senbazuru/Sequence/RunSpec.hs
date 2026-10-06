-- | Where a run starts: 'sheetState' on the repository's sheets, and on small
-- sheets made here for the cases no fixture has, such as a crease drawn F at
-- an angle or a face wound clockwise.
module Senbazuru.Sequence.RunSpec (spec) where

import Control.Monad (forM_)
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Sequence.Error (FoldedBy (..), SequenceError (..), SheetProblem (..))
import Senbazuru.Sequence.Record (MaterialPoint (..))
import Senbazuru.Sequence.Run
import Senbazuru.Sequence.Syntax (Span (..))
import Test.Hspec

spec :: Spec
spec = describe "the state a run starts from" $ do
  -- The fixture records its four corners folded in, at -180. Turns red if a
  -- file angle survives, or if a crease lying flat loses the M it was drawn
  -- with.
  it "lays the blintz flat and keeps its creases mountains" $ do
    state <- start "examples/blintz-base.fold"
    let frame = workingPattern state
    edgesFoldAngle frame `shouldBe` replicate (length (edgesVertices frame)) 0
    [edgesAssignment frame !! e | e <- [8 .. 11]] `shouldBe` replicate 4 Mountain
    faceOrders frame `shouldBe` []
    length (facesVertices frame) `shouldBe` 5

  -- The central square is largest, and its vertex mean is the centre, which
  -- is where `anchor centre` puts it too. Turns red if the anchor's face were
  -- not put first: folding holds its first face still.
  it "anchors the blintz at the centre of its central square, put first" $ do
    state <- start "examples/blintz-base.fold"
    stateAnchor state `shouldBe` MaterialPoint (V2 0.5 0.5)
    firstMean <- faceMean (workingPattern state) 0
    firstMean `shouldBe` V2 0.5 0.5

  -- All four faces tie on area; faces 0 and 3 tie on height, and face 3 is
  -- further left. Turns red if ties went by face id or by the highest mean.
  it "breaks a tie on area by the lowest and then the leftmost vertex mean" $ do
    state <- start "examples/quarter-fold-steps.fold"
    stateAnchor state `shouldBe` MaterialPoint (V2 0.25 0.25)
    firstMean <- faceMean (workingPattern state) 0
    firstMean `shouldBe` V2 0.25 0.25

  -- A sheet halved at x = 1/2 - 1e-13: the right half is larger by 2e-13, a
  -- difference rounding could make, so the halves tie on area and on height,
  -- and the left half wins as the leftmost. Turns red if areas were compared
  -- exactly, when the right half would win.
  it "treats areas that differ only by rounding as tied" $ do
    let x = 0.5 - 1e-13
        halves =
          emptyFrame
            { verticesCoords = [[0, 0], [x, 0], [1, 0], [1, 1], [x, 1], [0, 1]],
              edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0), (1, 4)]],
              edgesAssignment = replicate 6 Border ++ [Mountain]
            }
    state <- right (sheetState (withKey (const halves) squareSheet))
    case stateAnchor state of
      MaterialPoint (V2 ax _) -> ax `shouldSatisfy` (< 0.5)

  -- crane.fold writes no angles: 58 M, 41 V, 20 F and 10 B. Turns red if any
  -- letter is rewritten, F at 0 included.
  it "keeps every crease's letter as drawn when nothing contradicts it" $ do
    file <- load "examples/crane.fold"
    state <- right (sheetState file)
    edgesAssignment (workingPattern state) `shouldBe` edgesAssignment (keyFrame file)

  -- F means unfolded, so an F at an angle contradicts itself and the angle
  -- is believed. U says only that the direction is undecided, so it stays U
  -- at any angle. Turns red if the angle were trusted over U, or F kept at an
  -- angle.
  it "believes an F crease's angle, and keeps U at any angle" $
    forM_ [(Flat, -90, Mountain), (Flat, 90, Valley), (Flat, 0, Flat), (Flat, 1e-11, Flat), (Unassigned, 45, Unassigned)] $ \(letter, angle, expected) -> do
      state <- right (sheetState (diagonal letter angle))
      let frame = workingPattern state
      [a | ((VertexId 0, VertexId 2), a) <- zip (edgesVertices frame) (edgesAssignment frame)] `shouldBe` [expected]
      edgesFoldAngle frame `shouldBe` replicate 5 0

  -- A face's normal points the way its ring turns, so a clockwise ring would
  -- face the other way from the file's +z.
  it "winds every face anticlockwise on the sheet" $ do
    state <- right (sheetState (squareWith [3, 2, 1, 0]))
    area <- faceArea (workingPattern state) 0
    area `shouldSatisfy` (> 0)
    forM_ ["examples/blintz-base.fold", "examples/crane.fold", "examples/bird-base.fold"] $ \path -> do
      frame <- workingPattern <$> start path
      areas <- mapM (faceArea frame) [0 .. length (facesVertices frame) - 1]
      areas `shouldSatisfy` all (> 0)

  it "starts sheet square as the unit square, anchored at its centre" $ do
    state <- right (sheetState squareSheet)
    length (facesVertices (workingPattern state)) `shouldBe` 1
    edgesAssignment (workingPattern state) `shouldBe` replicate 4 Border
    stateAnchor state `shouldBe` MaterialPoint (V2 0.5 0.5)

  describe "refuses a sheet that is not paper before folding" $ do
    -- The file keeps its paper in sixteen folded states, not a key frame.
    it "with an empty key frame, naming the file's frames" $ do
      file <- load "examples/bird-base-sequence.fold"
      sheetState file `shouldBe` Left (SheetHasNoVertices 16)
      explain (SheetRefused NoSpan "examples/bird-base-sequence.fold" (SheetHasNoVertices 16))
        `shouldSatisfy` T.isPrefixOf "sheet \"examples/bird-base-sequence.fold\": its key frame has no vertices; the file keeps its paper in 16 file_frames"

    it "already folded, by its relief or by its class" $ do
      file <- load "examples/simple.fold"
      case sheetState file of
        Left (SheetAlreadyFolded (ByRelief z)) -> z `shouldSatisfy` (> 0)
        other -> expectationFailure ("expected a relief refusal, got " <> show other)
      sheetState (withKey (\f -> f {frameClasses = ["foldedForm"]}) squareSheet) `shouldBe` Left (SheetAlreadyFolded ByClass)

    -- An L whose arms are a tenth wide: its corners average to a point in
    -- the empty quarter. Turns red if the anchor were taken without asking
    -- whether it lies on paper.
    it "whose default anchor falls outside its only face" $ do
      let l = [[0, 0], [1, 0], [1, 0.1], [0.1, 0.1], [0.1, 1], [0, 1]]
          frame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}
      case sheetState (withKey (const frame) squareSheet) of
        Left (DefaultAnchorOutside (V2 x y)) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 2.2 / 6) < 1e-12 && abs (b - 2.2 / 6) < 1e-12)
        other -> expectationFailure ("expected the anchor refused, got " <> show other)

    -- The same question on a face that is not convex but whose mean is on
    -- paper: a thick arm three long and a short one, the mean (7/6, 2/5) in
    -- the long arm. Turns red if a convex-only test were used, which calls the
    -- mean outside because it lies beyond the line of the short arm's inner
    -- side.
    it "but not a mean that lies on paper in a face that is not convex" $ do
      let l = [[0, 0], [3, 0], [3, 0.5], [0.5, 0.5], [0.5, 0.7], [0, 0.7]]
          frame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}
      state <- right (sheetState (withKey (const frame) squareSheet))
      case stateAnchor state of
        MaterialPoint (V2 x y) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 7 / 6) < 1e-12 && abs (b - 0.4) < 1e-12)
  where
    load path = loadFoldFile path >>= right
    start path = load path >>= right . sheetState
    -- The unit square cut by one crease from corner 0 to corner 2.
    diagonal letter angle =
      withKey
        ( \f ->
            f
              { edgesVertices = edgesVertices f ++ [(VertexId 0, VertexId 2)],
                edgesAssignment = edgesAssignment f ++ [letter],
                edgesFoldAngle = replicate 4 0 ++ [angle],
                facesVertices = []
              }
        )
        squareSheet
    squareWith ring = withKey (\f -> f {facesVertices = [map VertexId ring]}) squareSheet
    withKey change file = file {keyFrame = change (keyFrame file)}

-- | A face's ring on the sheet, from the frame's own vertices.
ringOf :: Frame -> Int -> IO [V2]
ringOf frame face = do
  points <- right (frameVertices frame)
  pure [V2 x y | VertexId i <- facesVertices frame !! face, let V3 x y _ = points !! i]

faceArea :: Frame -> Int -> IO Double
faceArea frame face = signedArea <$> ringOf frame face

faceMean :: Frame -> Int -> IO V2
faceMean frame face = do
  ring <- ringOf frame face
  let n = fromIntegral (length ring)
  pure (V2 (sum [x | V2 x _ <- ring] / n) (sum [y | V2 _ y <- ring] / n))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
