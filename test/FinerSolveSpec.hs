-- | A gallery's own finer solve as a solved pose's finer level (owner
-- decision 29): which finer meshes are the pose's mesh split into four and
-- hold the sheet as it does, how close the two solves must be, and what a
-- pose's screen and report take from it. The fixtures are the flat wing's
-- seed meshes, held as the gallery holds them. They lie in the plane z = 0,
-- so a vertex lifted along z by 1/600 is exactly 1 px away: 1/600 is no
-- double, but the roundings in writing it and in multiplying it back by 600
-- cancel.
module FinerSolveSpec (spec) where

import Data.Aeson (Value, object, (.=))
import Data.Aeson.Types (Pair)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FinerSolve
import PaperScreen (Turning (..))
import ScreenReport
import Senbazuru.Explain (explain)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (checkLocalTriangleContact)
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import Test.Hspec
import UncreasedSurface (uncreasedSurface)
import WingBending (BendingPiece (..), wingPiece)
import WingBendingGallery (wingScreen)

spec :: Spec
spec = describe "a gallery's own finer solve as a pose's finer level" $ do
  it "matches the 8-division wing to the 16-division one on the flat sheet, and to no other" $ do
    coarse <- flatWing 8
    fine <- flatWing 16
    same coarse fine `shouldBe` Right (SameFinerPose 0)
    -- The 24-division wing is the 8-division one split into nine, and the
    -- 8-division wing is no finer than itself.
    finest <- flatWing 24
    same coarse finest `shouldBe` Left (FinerTriangleCount 256 576)
    same coarse coarse `shouldBe` Left (FinerTriangleCount 256 64)

  -- The finer mesh's first triangle is a piece of coarse triangle 0 and its
  -- last a piece of the last coarse triangle, at the tip; its vertex 1 is the
  -- midpoint of coarse triangle 0's edge along the root.
  it "refuses a finer mesh with a triangle out of place or too many, a point out of place, or a vertex too many" $ do
    coarse <- flatWing 8
    fine <- flatWing 16
    let mesh = wingMesh fine
        spare = length (samples mesh) - 1
    case triangles mesh of
      first@(a, b, _) : rest -> same coarse (withMesh fine mesh {triangles = (a, b, spare) : rest}) `shouldBe` Left (MissingFinerTriangle 0 first)
      [] -> expectationFailure "the 16-division wing has no triangles"
    case reverse (triangles mesh) of
      final@(a, b, _) : rest -> same coarse (withMesh fine mesh {triangles = reverse ((a, b, 0) : rest)}) `shouldBe` Left (MissingFinerTriangle (length (triangles (wingMesh coarse)) - 1) final)
      [] -> expectationFailure "the 16-division wing has no triangles"
    same coarse (withMesh fine mesh {triangles = triangles mesh ++ take 1 (triangles mesh)}) `shouldBe` Left (FinerTriangleCount 256 257)
    case same coarse (withMesh fine (alterSample 1 (\s -> s {sampleMaterial = sampleMaterial s ^+^ V2 0 1e-6}) mesh)) of
      Left (MissingFinerPoint 0 p) -> norm (p ^-^ materialOf 1 mesh) `shouldSatisfy` (< 1e-12)
      other -> expectationFailure ("expected vertex 1's point missing, got " ++ show other)
    same coarse (withMesh fine mesh {samples = samples mesh ++ take 1 (samples mesh)}) `shouldBe` Left (AmbiguousFinerPoint 0 [0, spare + 1])
    case triangles (wingMesh coarse) of
      (a, b, _) : rest ->
        let broken = (wingMesh coarse) {triangles = (a, b, 999) : rest}
         in same (withMesh coarse broken) fine `shouldBe` Left (UnknownCoarseVertex 0 999)
      [] -> expectationFailure "the 8-division wing has no triangles"

  -- Vertex 0 lies in the held root. The midpoint between a held vertex at
  -- u = 1/8 and a free one at u = 1/4 is not held.
  it "refuses a finer solve that holds the sheet elsewhere" $ do
    coarse <- flatWing 8
    fine <- flatWing 16
    let root = materialOf 0 (wingMesh coarse)
    same coarse fine {wingHeld = IM.delete 0 (wingHeld fine)} `shouldBe` Left (DifferentHolds root)
    same coarse fine {wingHeld = IM.adjust (^+^ V3 0 0 0.01) 0 (wingHeld fine)} `shouldBe` Left (DifferentHolds root)
    case vertexAt (wingMesh fine) (V2 0.1875 (-0.24375)) of
      Just i -> case same coarse fine {wingHeld = IM.insert i (V3 0 0 0) (wingHeld fine)} of
        Left (DifferentHolds p) -> norm (p ^-^ V2 0.1875 (-0.24375)) `shouldSatisfy` (< 1e-12)
        other -> expectationFailure ("expected the midpoint's hold refused, got " ++ show other)
      Nothing -> expectationFailure "the 16-division wing has no vertex at (0.1875, -0.24375)"

  -- A free vertex in the middle of the wing, far from coarse triangle 0,
  -- whose number differs in the two meshes.
  it "counts two solves within the floor limit of each other at every vertex, and no further apart" $ do
    coarse <- flatWing 8
    fine <- flatWing 16
    let middle = V2 0.5 0
    (v, i) <- maybe (fail "no vertex at (0.5, 0)") pure ((,) <$> vertexAt (wingMesh coarse) middle <*> vertexAt (wingMesh fine) middle)
    v `shouldNotBe` i
    let lifted z = withMesh fine (alterSample i (\s -> s {position = position s ^+^ V3 0 0 z}) (wingMesh fine))
    same coarse (lifted (1 / 600)) `shouldBe` Right (SameFinerPose floorLimitPixels)
    case same coarse (lifted (1.01 / 600)) of
      Left (SolvesApart at pixels) -> (at, abs (pixels - 1.01) < 1e-9) `shouldBe` (v, True)
      other -> expectationFailure ("expected the solves refused as 1.01 px apart, got " ++ show other)
    case same coarse (lifted (0 / 0)) of
      Left (SolvesApart at pixels) -> (at, isNaN pixels) `shouldBe` (v, True)
      other -> expectationFailure ("expected a distance that is no number refused, got " ++ show other)

  it "gives a pose its finer solve's own turning, and nothing where that solve does not count" $ do
    coarse <- flatWing 8
    fine <- flatWing 16
    finest <- flatWing 24
    let pose = handOver "wing-8-0" coarse (Turning 0 0)
        creased = handOver "wing-16-0" fine (Turning 3 120)
    finerLevel "16 divisions" creased pose `shouldBe` (Just (Turning 3 120), ["finerSolve" .= object ["id" .= text "wing-16-0", "label" .= text "16 divisions", "apartPixels" .= (0 :: Double)]])
    -- A finer solve its gallery does not accept does not count, however
    -- close it lies (owner decision 31).
    finerLevel "16 divisions" creased {pendingAccepted = False} pose
      `shouldBe` (Nothing, ["finerSolve" .= object ["id" .= text "wing-16-0", "label" .= text "16 divisions", "refused" .= explain FinerNotAccepted]])
    finerLevel "24 divisions" (handOver "wing-24-0" finest (Turning 0 0)) pose
      `shouldBe` (Nothing, ["finerSolve" .= object ["id" .= text "wing-24-0", "label" .= text "24 divisions", "refused" .= explain (FinerTriangleCount 256 576)]])
    -- The screen takes the finer level it is given: none leaves it not
    -- measured, and a finer solve with a join past the threshold fails a
    -- pose that has none.
    verdicts <- mapM (fmap (verdictOverall . screenVerdict) . screenAt 8) [Nothing, Just (Turning 0 0), Just (Turning 3 120)]
    verdicts `shouldBe` [NotMeasured, Passes, Fails]

  it "pairs a gallery's poses by the ids it names, and refuses a name it does not have or has twice" $ do
    coarse <- flatWing 8
    fine <- flatWing 16
    let poses = [handOver "coarse" coarse (Turning 0 0), handOver "fine" fine (Turning 3 120)]
    finishReports [("coarse", "fine", "16 divisions")] poses
      `shouldBe` Right
        [ object ["pose" .= text "coarse", "finerJoins" .= Just (3 :: Int), "finerSolve" .= object ["id" .= text "fine", "label" .= text "16 divisions", "apartPixels" .= (0 :: Double)]],
          object ["pose" .= text "fine", "finerJoins" .= (Nothing :: Maybe Int)]
        ]
    finishReports [("coarse", "finer", "")] poses `shouldSatisfy` isLeft
    finishReports [("coars", "fine", "")] poses `shouldSatisfy` isLeft
    finishReports [("coarse", "fine", ""), ("coarse", "fine", "")] poses `shouldSatisfy` isLeft
    finishReports [] (poses ++ take 1 poses) `shouldSatisfy` isLeft

-- | A flat wing as its gallery holds it: the points held, each with where,
-- and the seed mesh.
data Wing = Wing {wingHeld :: IM.IntMap V3, wingMesh :: MaterialMesh}

flatWing :: Int -> IO Wing
flatWing divisions = do
  piece <- right (wingPiece divisions 0)
  pure (Wing (piecePins piece) (pieceMesh piece))

withMesh :: Wing -> MaterialMesh -> Wing
withMesh wing mesh = wing {wingMesh = mesh}

same :: Wing -> Wing -> Either FinerSolveRefusal SameFinerPose
same coarse fine = sameFinerPose (wingHeld coarse) (wingMesh coarse) (wingHeld fine) (wingMesh fine)

-- | A pose as a gallery hands it over, whose report says whose it is and
-- how many joins its finer level has, so that a report routed to the wrong
-- pose, or given the wrong finer level, shows.
handOver :: Text -> Wing -> Turning -> Pending
handOver name wing turning = Pending name True (wingHeld wing) (wingMesh wing) turning report
  where
    report :: Maybe Turning -> [Pair] -> Either Text Value
    report finer keys = Right (object (("pose" .= name) : ("finerJoins" .= fmap turningJoins finer) : keys))

-- | The flat wing's screen at this many divisions, at a given finer level,
-- as the gallery screens it.
screenAt :: Int -> Maybe Turning -> IO Screen
screenAt divisions finer = do
  piece <- right (wingPiece divisions 0)
  let mesh = pieceMesh piece
  sheet <- right (uncreasedSurface mesh)
  contact <- right (checkLocalTriangleContact (V3 0 0 1) [] mesh)
  fst <$> right (wingScreen sheet contact (pieceHinges piece) False mesh finer)

vertexAt :: MaterialMesh -> V2 -> Maybe Int
vertexAt mesh p = case [i | (i, s) <- zip [0 ..] (samples mesh), norm (sampleMaterial s ^-^ p) < 1e-12] of
  [i] -> Just i
  _ -> Nothing

materialOf :: Int -> MaterialMesh -> V2
materialOf i mesh = maybe (V2 (0 / 0) (0 / 0)) sampleMaterial (lookup i (zip [0 ..] (samples mesh)))

alterSample :: Int -> (Sample V2 -> Sample V2) -> MaterialMesh -> MaterialMesh
alterSample i f mesh = mesh {samples = [if j == i then f s else s | (j, s) <- zip [0 ..] (samples mesh)]}

text :: Text -> Text
text = id

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
