-- | Naming paper on a flat state, on the blintz: at its start, after its
-- first corner is folded (the study's recipe supplies that state), and on
-- sheets made here for what the blintz cannot show, a sheet that is not a
-- square and one that is not the unit square.
module Senbazuru.Sequence.ResolveSpec (spec) where

import BlintzSequence (BlintzMove (..), buildBlintzSequence)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Sequence.Error (ResolveProblem (..))
import Senbazuru.Sequence.Resolve
import Senbazuru.Sequence.Run (sheetState, squareSheet, workingPattern)
import Senbazuru.Sequence.Syntax (Compass (..), Corner (..), Line (..), Name (..), Point (..))
import Test.Hspec

spec :: Spec
spec = describe "naming paper on a flat state" $ do
  blintz <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  start <- runIO (right (sheetState blintz) >>= flatOf . workingPattern)
  -- The recipe's state after its first move: corner south-east folded behind
  -- onto the centre.
  afterFirst <- runIO (right (buildBlintzSequence (keyFrame blintz)) >>= \turns -> right (flatState (blintzStart (turns !! 1))))

  it "names the sheet's corners, centre and midpoints where they lay" $ do
    materialPoint start (CornerOf SouthEast) `shouldBe` Right (V2 1 0)
    materialPoint start Centre `shouldBe` Right (V2 0.5 0.5)
    materialPoint start (AtSheet (1 / 4) (3 / 4)) `shouldBe` Right (V2 0.25 0.75)
    materialPoint start (MidpointOf (CornerOf SouthWest) (CornerOf NorthEast)) `shouldBe` Right (V2 0.5 0.5)
    materialPoint start (FractionAlong (1 / 4) (CornerOf SouthWest) (CornerOf SouthEast)) `shouldBe` Right (V2 0.25 0)
    materialPoint start (MidpointOfEdge North) `shouldBe` Right (V2 0.5 1)

  -- D2's example: on a sheet 400 across with its south-west corner at
  -- (-200, -200), (29/50, 2/5) is (32, -40). Turns red if sheet lengths were
  -- taken as the file's own units, or measured from the origin.
  it "measures a typed point in sheet lengths on a sheet of any size" $ do
    let big = squareSheet {keyFrame = (keyFrame squareSheet) {verticesCoords = [[-200, -200], [200, -200], [200, 200], [-200, 200]]}}
    st <- right (sheetState big) >>= flatOf . workingPattern
    point <- right (materialPoint st (AtSheet (29 / 50) (2 / 5)))
    near point (V2 32 (-40)) `shouldBe` True

  -- An L has no north-east corner: its box does, at (3, 0.7), and its
  -- outline does not.
  it "refuses a compass corner where the sheet's outline has none" $ do
    let l = [[0, 0], [3, 0], [3, 0.5], [0.5, 0.5], [0.5, 0.7], [0, 0.7]]
        sheet = squareSheet {keyFrame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}}
    st <- right (sheetState sheet) >>= flatOf . workingPattern
    materialPoint st (CornerOf NorthEast) `shouldBe` Left (NoCornerThere NorthEast)
    materialPoint st (CornerOf SouthWest) `shouldBe` Right (V2 0 0)

  -- (1/2, 1/2000) is 5e-4 sheet lengths from vertex 4 at (1/2, 0): inside
  -- the band, outside the tolerance, so the author meant the vertex. Turns red
  -- if typed points were never guarded, or if a point on the vertex were
  -- refused as well.
  it "refuses a typed point near a vertex, and takes one on it as the vertex" $ do
    case positionOf 1e-3 start (AtSheet (1 / 2) (1 / 2000)) of
      Left (NearMiss written 4 (V2 0.5 0) distance) -> do
        written `shouldBe` (1 / 2, 1 / 2000)
        distance `shouldSatisfy` (\d -> abs (d - 5e-4) < 1e-12)
      other -> expectationFailure ("expected a near miss of vertex 4, got " <> show other)
    positionOf 1e-3 start (AtSheet (1 / 2) 0) `shouldBe` Right (V2 0.5 0)
    positionOf 1e-3 start (AtSheet (1 / 2) (1 / 50)) `shouldBe` Right (V2 0.5 0.02)
    positionOf 1e-3 start (AtSheet 2 2) `shouldBe` Left (OffThePaper (V2 2 2))

  -- The first fold of the blintz: O2 of (1, 0) and (1/2, 1/2) is x - y = 1/2,
  -- which runs along edge 8 and nothing else.
  it "lays the blintz's first corner onto the centre about edge 8" $ do
    line <- right (foldLine 1e-3 start (Onto (CornerOf SouthEast) Centre))
    near (linePoint line) (V2 0.75 0.25) `shouldBe` True
    hingeAlong start line `shouldBe` Right [EdgeId 8]

  -- After the first fold, corner south-east lies on the centre. A line worked
  -- out on the flat sheet would put it at (1, 0) still. Turns red if
  -- positions were material rather than folded.
  it "finds a folded corner where it now is, and the next fold's hinge from there" $ do
    corner <- right (positionOf 1e-3 afterFirst (CornerOf SouthEast))
    near corner (V2 0.5 0.5) `shouldBe` True
    line <- right (foldLine 1e-3 afterFirst (Onto (CornerOf NorthEast) Centre))
    hingeAlong afterFirst line `shouldBe` Right [EdgeId 9]

  describe "refuses a fold line" $ do
    -- The diagonal crosses the central square, where no crease runs.
    it "that crosses paper where no crease runs, until creasing is run" $ do
      line <- right (foldLine 1e-3 start (Segment (CornerOf SouthWest) (CornerOf NorthEast)))
      case hingeAlong start line of
        Left (NotRunYet _) -> pure ()
        other -> expectationFailure ("expected creasing to be not run yet, got " <> show other)

    it "that runs along no crease" $ do
      line <- right (foldLine 1e-3 start (Segment (CornerOf SouthWest) (CornerOf SouthEast)))
      hingeAlong start line `shouldBe` Left NoSolution

    it "whose two points are one" $
      foldLine 1e-3 start (Onto Centre Centre) `shouldBe` Left DegenerateConstruction

    it "of a form not run yet" $
      foldLine 1e-3 start (HingeOf (Name "c1")) `shouldBe` Left (NotRunYet "hinge of")

  -- The anchor's slot: strictly inside one face. A point on edge 8 is
  -- between the square and the corner.
  it "puts a region point in the one face it lies inside" $ do
    regionFace start (V2 0.5 0.5) `shouldBe` Right (FaceId 0)
    regionFace start (V2 0.75 0.25) `shouldBe` Left (NotInOneFace (V2 0.75 0.25) 0)

  -- Corner south-east turned to -90 stands out of the plane.
  it "refuses paper that does not lie flat" $ do
    paper90 <- workingPattern <$> right (sheetState blintz)
    folded <- right (foldFrameWith paper90 {edgesFoldAngle = [if e == 8 then -90 else 0 | e <- [0 .. length (edgesVertices paper90) - 1]]})
    case flatState folded of
      Left (ConstructionInTheAir relief) -> relief `shouldSatisfy` (> 0)
      Left other -> expectationFailure ("expected the paper in the air, got " <> show other)
      Right _ -> expectationFailure "expected the paper in the air, and it was taken as flat"
  where
    flatOf frame = right (foldFrameWith frame) >>= right . flatState
    near p q = norm (p ^-^ q) < 1e-12

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
