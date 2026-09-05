-- |
-- Tests for laying a whole folding sequence out as one page.
--
-- The property worth stating loudest is that every figure is drawn through one
-- camera. It is easy to get wrong by asking each frame what /it/ would like,
-- and the result is subtle rather than obviously broken: the reader is moved
-- around the model between figures, and the shared extent that holds the scale
-- steady becomes a union of boxes measured in different projections.
module Senbazuru.Render.StepsSpec (spec) where

import Senbazuru.Diagram (Diagram (..), Shape (..))
import Senbazuru.Diagram.Layout (Grid (..), defaultGrid)
import Senbazuru.Diagram.Style (defaultTheme)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types (Assignment (..), Frame (..), VertexId (..), emptyFrame)
import Senbazuru.Render.Camera (isometric, topDown)
import Senbazuru.Render.Steps
import Test.Hspec

-- | A square sheet at the given heights, one per corner, so that passing
-- anything but zeroes makes the frame leave the plane.
sheet :: [Double] -> Frame
sheet zs =
  emptyFrame
    { verticesCoords = zipWith (\(x, y) z -> [x, y, z]) [(0, 0), (1, 0), (1, 1), (0, 1)] zs,
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 0)
        ],
      edgesAssignment = replicate 4 Border
    }

flatSheet :: Frame
flatSheet = sheet [0, 0, 0, 0]

solidSheet :: Frame
solidSheet = sheet [0, 0, 0.7, 0]

grid :: Grid
grid = defaultGrid defaultTheme

page :: Maybe a1 -> [Frame] -> Either StepError (Maybe Diagram)
page _ = stepPage defaultTheme grid Nothing False

spec :: Spec
spec = do
  describe "one camera for the whole page" $ do
    it "views a sequence that ends in the air isometrically throughout" $ do
      -- Not one figure from above and the next from an angle. Asserted against
      -- the explicit camera rather than by inspecting coordinates, so the test
      -- says what it means.
      let frames = [flatSheet, solidSheet]
      stepPage defaultTheme grid Nothing False frames
        `shouldBe` stepPage defaultTheme grid (Just isometric) False frames

    it "views a sequence that stays flat from above throughout" $ do
      let frames = [flatSheet, flatSheet]
      stepPage defaultTheme grid Nothing False frames
        `shouldBe` stepPage defaultTheme grid (Just topDown) False frames

    it "is not the same page either way, so the tests above can fail" $ do
      -- Guards the two above: if the cameras happened to agree on this input
      -- they would pass without saying anything.
      let frames = [flatSheet, solidSheet]
      stepPage defaultTheme grid (Just topDown) False frames
        `shouldNotBe` stepPage defaultTheme grid (Just isometric) False frames

  describe "which frames are steps" $ do
    it "skips a frame with no geometry in it" $ do
      -- FOLD keeps file metadata in the same object as the first frame, so a
      -- file that puts every step in file_frames has a key frame holding a
      -- title and nothing else. That is not a step.
      let withMetadataFrame = [emptyFrame {frameTitle = Just "just a title"}, flatSheet, flatSheet]
      fmap (fmap (length . labelsOf)) (page Nothing withMetadataFrame)
        `shouldBe` Right (Just 2)

    it "has nothing to lay out when no frame has any geometry" $
      page Nothing [emptyFrame, emptyFrame] `shouldBe` Right Nothing

    it "numbers the figures, not the frames they came from" $ do
      let withMetadataFrame = [emptyFrame, flatSheet, flatSheet]
      fmap (fmap labelsOf) (page Nothing withMetadataFrame)
        `shouldBe` Right (Just ["1", "2"])

  describe "when a frame will not draw" $
    it "says which frame it was" $ do
      -- Told only that a file will not draw, someone holding a twenty-step
      -- sequence has to bisect it by hand. Note the index counts frames in the
      -- file, so the skipped metadata frame still occupies number zero.
      let broken = flatSheet {verticesCoords = [[0]]}
      page Nothing [emptyFrame, flatSheet, broken]
        `shouldBe` Left (StepError 2 (VertexCoordTooShort (VertexId 0) 1))

labelsOf :: Diagram -> [String]
labelsOf d = [show' t | Label _ _ _ t <- diagramShapes d]
  where
    show' = filter (/= '"') . show
