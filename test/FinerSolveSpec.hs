-- | A gallery's own finer solve as a solved pose's finer level (owner
-- decision 29): which finer meshes are the pose's mesh split into four, how
-- close the two solves must be, and what a pose's screen and report take
-- from it. The fixtures are the flat wing's seed meshes, which lie in the
-- plane z = 0, so a vertex moved along z by 1/600 is exactly 1 px away.
module FinerSolveSpec (spec) where

import Data.Aeson (object, (.=))
import Data.Either (isLeft)
import Data.Text (Text)
import FinerSolve
import FoldBending (hingeBends)
import PaperScreen (Turning (..), sheetChords)
import ScreenReport
import Senbazuru.Explain (explain)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (checkLocalTriangleContact)
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import SurfaceScreen (surfaceScreen)
import Test.Hspec
import UncreasedSurface (uncreasedSurface)
import WingBending (BendingPiece (..), wingPiece)

spec :: Spec
spec = describe "a gallery's own finer solve as a pose's finer level" $ do
  it "matches the 8-division wing to the 16-division one on the flat sheet, and to no other" $ do
    (coarse, _) <- flatWing 8
    (fine, _) <- flatWing 16
    sameFinerPose coarse fine `shouldBe` Right (SameFinerPose 0)
    -- The 24-division wing is the 8-division one split into nine, and the
    -- 8-division wing is no finer than itself.
    (finest, _) <- flatWing 24
    sameFinerPose coarse finest `shouldBe` Left (FinerTriangleCount 256 576)
    sameFinerPose coarse coarse `shouldBe` Left (FinerTriangleCount 256 64)

  -- Fine vertex 0 is coarse vertex 0's corner of coarse triangle 0, and fine
  -- vertex 1 the midpoint of that triangle's edge along the root.
  it "refuses a finer mesh with a triangle, a point or a vertex too many out of place" $ do
    (coarse, _) <- flatWing 8
    (fine, _) <- flatWing 16
    case triangles fine of
      (a, b, _) : rest -> sameFinerPose coarse fine {triangles = (a, b, length (samples fine) - 1) : rest} `shouldBe` Left (MissingFinerTriangle 0)
      [] -> expectationFailure "the 16-division wing has no triangles"
    sameFinerPose coarse fine {triangles = triangles fine ++ take 1 (triangles fine)} `shouldBe` Left (FinerTriangleCount 256 257)
    sameFinerPose coarse (alterSample 1 (\s -> s {sampleMaterial = sampleMaterial s ^+^ V2 0 1e-6}) fine) `shouldBe` Left (MissingFinerPoint 0)
    sameFinerPose coarse fine {samples = samples fine ++ take 1 (samples fine)} `shouldBe` Left (AmbiguousFinerPoint 0)

  it "counts two solves within the floor limit of each other as one pose, and no further apart" $ do
    (coarse, _) <- flatWing 8
    (fine, _) <- flatWing 16
    let lifted z = alterSample 0 (\s -> s {position = position s ^+^ V3 0 0 z}) fine
    sameFinerPose coarse (lifted (1 / 600)) `shouldBe` Right (SameFinerPose floorLimitPixels)
    case sameFinerPose coarse (lifted (2 / 600)) of
      Left (SolvesApart vertex pixels) -> (vertex, abs (pixels - 2) < 1e-9) `shouldBe` (0, True)
      other -> expectationFailure ("expected the solves refused as 2 px apart, got " ++ show other)

  it "gives a pose its finer solve's own turning, and nothing where that solve does not count" $ do
    (coarse, coarseScreen) <- flatWing 8
    (fine, fineScreen) <- flatWing 16
    verdictOverall (screenVerdict coarseScreen) `shouldBe` NotMeasured
    let (counted, keys) = withFinerSolve "wing-16-0" "solved at 16 divisions" (fineScreen, fine) (coarseScreen, coarse)
    screenTurningFiner counted `shouldBe` Just (screenTurning fineScreen)
    verdictOverall (screenVerdict counted) `shouldBe` Passes
    object keys `shouldBe` object ["finerSolve" .= object ["id" .= text "wing-16-0", "label" .= text "solved at 16 divisions", "apartPixels" .= (0 :: Double)]]
    -- The finer level is the finer solve's, not the pose's own: a finer solve
    -- with a join past the threshold fails a pose that has none.
    let creased = fineScreen {screenTurning = Turning 3 120}
    screenTurningFiner (fst (withFinerSolve "wing-16-0" "" (creased, fine) (coarseScreen, coarse))) `shouldBe` Just (Turning 3 120)
    (finest, finestScreen) <- flatWing 24
    let (refused, refusedKeys) = withFinerSolve "wing-24-0" "solved at 24 divisions" (finestScreen, finest) (coarseScreen, coarse)
    refused `shouldBe` coarseScreen
    object refusedKeys `shouldBe` object ["finerSolve" .= object ["id" .= text "wing-24-0", "label" .= text "solved at 24 divisions", "refused" .= explain (FinerTriangleCount 256 576)]]

  it "pairs a gallery's poses by the ids it names, and refuses a name it does not have" $ do
    (coarse, coarseScreen) <- flatWing 8
    (fine, fineScreen) <- flatWing 16
    let report final keys = object (("finerJoins" .= fmap turningJoins (screenTurningFiner final)) : keys)
        poses = [Pending "coarse" coarseScreen coarse report, Pending "fine" fineScreen fine report]
    reports <- right (finishReports [("coarse", "fine", "solved at 16 divisions")] poses)
    reports
      `shouldBe` [ object ["finerJoins" .= Just (0 :: Int), "finerSolve" .= object ["id" .= text "fine", "label" .= text "solved at 16 divisions", "apartPixels" .= (0 :: Double)]],
                   object ["finerJoins" .= (Nothing :: Maybe Int)]
                 ]
    finishReports [("coarse", "finer", "")] poses `shouldSatisfy` isLeft

-- | The flat wing's seed mesh at this many divisions, and its screen.
flatWing :: Int -> IO (MaterialMesh, Screen)
flatWing divisions = do
  piece <- right (wingPiece divisions 0)
  let mesh = pieceMesh piece
  sheet <- right (uncreasedSurface mesh)
  chords <- right (sheetChords mesh)
  bends <- right (hingeBends (pieceHinges piece) mesh)
  contact <- right (checkLocalTriangleContact (V3 0 0 1) [] mesh)
  screen <- right (surfaceScreen sheet chords contact bends mesh)
  pure (mesh, screen)

alterSample :: Int -> (Sample V2 -> Sample V2) -> MaterialMesh -> MaterialMesh
alterSample i f mesh = mesh {samples = [if j == i then f s else s | (j, s) <- zip [0 ..] (samples mesh)]}

text :: Text -> Text
text = id

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
