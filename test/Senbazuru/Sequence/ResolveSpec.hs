-- | Naming paper on a flat state, on the blintz: at its start, after its
-- first corner is folded (the study's recipe supplies that state), and on
-- sheets made here for what the blintz cannot show, a sheet that is not a
-- square and one that is not the unit square.
module Senbazuru.Sequence.ResolveSpec (spec) where

import BlintzSequence (BlintzMove (..), buildBlintzSequence)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Sequence.Error (CandidateLine (..), ResolveProblem (..))
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
      foldLine 1e-3 start (HingeOf (Name "c1")) `shouldBe` Left (NotRunYet "\"hinge of NAME\"")

  -- edge S is the line the sheet's side lies along now. PRD 02 §4.6's
  -- worked case: once corner south-east is folded to the centre, edge
  -- south's east half runs from (1/2, 0) to (1/2, 1/2), at right angles to
  -- its west half, and the side names no line. Edge north is untouched.
  describe "names an edge as a line" $ do
    it "along the side, while the side lies straight" $ do
      FoldLine p d <- right (foldLine 1e-3 start (EdgeOf South))
      onLine p d (V2 0 0) `shouldBe` True
      onLine p d (V2 1 0) `shouldBe` True
      FoldLine q e <- right (foldLine 1e-3 afterFirst (EdgeOf North))
      onLine q e (V2 0 1) `shouldBe` True
      onLine q e (V2 1 1) `shouldBe` True

    -- A square set as a diamond: each side of its box touches the outline
    -- at a corner only, so no edge of the sheet lies along it.
    it "and refuses a side of the box no edge of the sheet lies along" $ do
      let diamond = squareSheet {keyFrame = (keyFrame squareSheet) {verticesCoords = [[0.5, 0], [1, 0.5], [0.5, 1], [0, 0.5]]}}
      st <- right (sheetState diamond) >>= flatOf . workingPattern
      foldLine 1e-3 st (EdgeOf North) `shouldBe` Left (EdgeNotStraight North [])

    it "and refuses one a fold has bent, naming its pieces" $
      case foldLine 1e-3 afterFirst (EdgeOf South) of
        Left (EdgeNotStraight South pieces) -> do
          length pieces `shouldBe` 2
          any (samePiece (V2 0.5 0, V2 0.5 0.5)) pieces `shouldBe` True
          any (samePiece (V2 0 0, V2 0.5 0)) pieces `shouldBe` True
        other -> expectationFailure ("expected edge south refused as bent, got " <> show other)

  -- L1 to L2 lays one line onto another (Huzita-Hatori's third
  -- construction). On the flat blintz, where the paper is where it lay.
  describe "lays a line onto a line" $ do
    -- Edges west and east are parallel: one answer, midway, at x = 1/2.
    it "midway between two parallel lines" $ do
      FoldLine p d <- right (foldLine 1e-3 start (LineOnto (EdgeOf West) (EdgeOf East) Nothing))
      onLine p d (V2 0.5 0) `shouldBe` True
      onLine p d (V2 0.5 1) `shouldBe` True

    -- Edges south and east cross at corner south-east. Of the two lines
    -- halving the angles there, one runs off the paper from the corner and is
    -- never taken; the other is the diagonal to corner north-west.
    it "on the line halving their angle that crosses paper" $ do
      FoldLine p d <- right (foldLine 1e-3 start (LineOnto (EdgeOf South) (EdgeOf East) Nothing))
      onLine p d (V2 0 1) `shouldBe` True
      onLine p d (V2 1 0) `shouldBe` True

    -- Near corner south-east, a stretch of edge south onto the far half of
    -- edge east. Laid onto edge east's line, the stretch lands on its near
    -- half, so neither answer lays stretch onto stretch; the one off the paper
    -- is set aside, and the diagonal is the only answer left. Turns red if
    -- answers crossing no paper were kept, which would ask for nearest.
    it "never on an answer that crosses no paper" $ do
      FoldLine p d <- right (foldLine 1e-3 start (LineOnto (Segment (AtSheet (3 / 4) 0) (CornerOf SouthEast)) (Segment (MidpointOfEdge East) (CornerOf NorthEast)) Nothing))
      onLine p d (V2 0 1) `shouldBe` True
      onLine p d (V2 1 0) `shouldBe` True

    -- From the centre, one stretch runs west and the other north. Both
    -- diagonals cross the paper, but only x + y = 1 lays the first onto the
    -- second; y = x lays it onto the line south of the centre, where the
    -- second stretch is not. Turns red if the preference were dropped, which
    -- would ask for nearest.
    it "on the answer that lays one stretch onto the other, when both cross paper" $ do
      FoldLine p d <- right (foldLine 1e-3 start (LineOnto (Segment (MidpointOfEdge West) Centre) (Segment Centre (MidpointOfEdge North)) Nothing))
      onLine p d (V2 0 1) `shouldBe` True
      onLine p d (V2 1 0) `shouldBe` True

    -- The midlines cross at the centre, and each diagonal lays one onto the
    -- other: two answers, so nearest P chooses, and the centre, on both,
    -- cannot.
    it "asks nearest P to choose between two answers, and refuses a point as near to both" $ do
      let midlines = LineOnto (Segment (MidpointOfEdge West) (MidpointOfEdge East)) (Segment (MidpointOfEdge South) (MidpointOfEdge North))
      case foldLine 1e-3 start (midlines Nothing) of
        Left (NeedsNearest answers) -> map candidateOnPaper answers `shouldBe` [True, True]
        other -> expectationFailure ("expected nearest asked for, got " <> show other)
      FoldLine p d <- right (foldLine 1e-3 start (midlines (Just (CornerOf NorthEast))))
      onLine p d (V2 0 0) `shouldBe` True
      onLine p d (V2 1 1) `shouldBe` True
      case foldLine 1e-3 start (midlines (Just Centre)) of
        Left (NearestAmbiguous at answers) -> (at, length answers) `shouldBe` (V2 0.5 0.5, 2)
        other -> expectationFailure ("expected the centre refused as near to both, got " <> show other)

    it "and refuses two lines that are one" $
      foldLine 1e-3 start (LineOnto (EdgeOf South) (Segment (CornerOf SouthWest) (CornerOf SouthEast)) Nothing) `shouldBe` Left DegenerateConstruction

  -- The anchor's slot: strictly inside one face. A point on edge 8 is
  -- between the square and the corner.
  it "puts a region point in the one face it lies inside" $ do
    regionFace start (V2 0.5 0.5) `shouldBe` Right (FaceId 0)
    regionFace start (V2 0.75 0.25) `shouldBe` Left (NotInOneFace (V2 0.75 0.25) 0)
    -- Off the paper altogether is said as that, not as lying between faces.
    regionFace start (V2 2 2) `shouldBe` Left (OffThePaper (V2 2 2))

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
    onLine p d x = abs (cross2 d (x ^-^ p)) < 1e-12
    samePiece (a, b) (c, e) = (near a c && near b e) || (near a e && near b c)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
