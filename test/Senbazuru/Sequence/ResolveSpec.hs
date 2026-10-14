-- | Naming paper on a flat state, on the blintz: at its start, after its
-- first corner is folded (a run of the language's blintz supplies that
-- state), and on
-- sheets made here for what the blintz cannot show, a sheet that is not a
-- square and one that is not the unit square; and on two example files, the
-- accordion, for a hinge's stretches, and the crane, folded by its file's own
-- angles, for the line M4's crane sequence folds along.
module Senbazuru.Sequence.ResolveSpec (spec) where

import Data.Map.Strict qualified as M
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (cross2)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Surface (surfaceFrame)
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (CandidateLine (..), ResolveProblem (..), TakenBecause (..))
import Senbazuru.Sequence.Record (Run (..), recordAfter, recordAngles)
import Senbazuru.Sequence.Resolve
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, squareSheet, workingPattern)
import Senbazuru.Sequence.Syntax (Compass (..), Corner (..), Line (..), Name (..), Point (..))
import Test.Hspec
import Test.SequenceExamples qualified as Examples

spec :: Spec
spec = describe "naming paper on a flat state" $ do
  blintz <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  start <- runIO (right (sheetState blintz) >>= flatOf . workingPattern)
  -- The state after the blintz's first move, corner south-east folded behind
  -- onto the centre: the sheet's working pattern with the angles and orders
  -- the run's first record ends at.
  afterFirst <- runIO $ do
    run <- right (checkSequence Examples.blintz >>= runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" blintz) . elaborate)
    paper <- workingPattern <$> right (sheetState blintz)
    case runRecords run of
      first' : _ -> right (foldFrameWith paper {edgesFoldAngle = snd (recordAngles first'), faceOrders = faceOrders (surfaceFrame (recordAfter first'))}) >>= right . flatState
      [] -> fail "the blintz made no record"

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
    -- The diagonal crosses the central square, face 0, and the two corner
    -- triangles at its ends, where no crease runs. A runner creases such
    -- paper first (chordsAcross), so the hinge is asked for only once nothing
    -- is crossed.
    it "that crosses paper where no crease runs" $ do
      line <- right (foldLine 1e-3 start (Segment (CornerOf SouthWest) (CornerOf NorthEast)))
      crossedFaces start line `shouldBe` [FaceId 0, FaceId 1, FaceId 3]
      case hingeAlong start line of
        Left (NotRunYet _) -> pure ()
        other -> expectationFailure ("expected the crossed paper refused, got " <> show other)

    it "that runs along no crease" $ do
      line <- right (foldLine 1e-3 start (Segment (CornerOf SouthWest) (CornerOf SouthEast)))
      hingeAlong start line `shouldBe` Left NoSolution

    it "whose two points are one" $
      foldLine 1e-3 start (Onto Centre Centre) `shouldBe` Left DegenerateConstruction

    it "of a form not run yet" $
      foldLine 1e-3 start (CreaseOf (Name "c1")) `shouldBe` Left (NotRunYet "\"crease of NAME\"")

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

    -- The same stretches, with a nearest P the preference did not need. It
    -- has to agree (owner decision 41): corner north-west lies on x + y = 1,
    -- the answer taken, and is accepted; midpoint of edge south lies as near
    -- to both diagonals and points at neither; corner south-west lies on
    -- y = x, the other, and is refused rather than ignored. Turns red if
    -- nearest were ignored again, or a point as near to both refused.
    it "refuses a nearest P lying nearer another answer than the one the preference takes" $ do
      let halves = LineOnto (Segment (MidpointOfEdge West) Centre) (Segment Centre (MidpointOfEdge North)) . Just
      mapM_
        ( \p -> do
            FoldLine o d <- right (foldLine 1e-3 start (halves p))
            onLine o d (V2 0 1) `shouldBe` True
            onLine o d (V2 1 0) `shouldBe` True
        )
        [CornerOf NorthWest, MidpointOfEdge South]
      case foldLine 1e-3 start (halves (CornerOf SouthWest)) of
        Left (NearestDisagrees at taken LaysStretchOntoStretch pointed) -> do
          at `shouldBe` V2 0 0
          (candidateOnPaper taken, candidateOnPaper pointed) `shouldBe` (True, True)
          candidateAlong taken `shouldSatisfy` near (V2 (sqrt 0.5) (-(sqrt 0.5)))
          candidateAlong pointed `shouldSatisfy` near (V2 (sqrt 0.5) (sqrt 0.5))
        other -> expectationFailure ("expected nearest refused as pointing elsewhere, got " <> show other)

    -- Two stretches whose lines cross a quarter below the paper, under its
    -- middle. Of the lines halving them, x = 1/2 crosses the paper and
    -- y = -1/4 does not, so the first is taken before nearest is read.
    -- Corner south-west lies a quarter from the second and a half from the
    -- first: it points at an answer that can never be taken, and is refused
    -- with that answer marked as crossing no paper. Turns red if answers off
    -- the paper were left out of the comparison.
    it "refuses a nearest P lying nearer an answer that crosses no paper" $
      case foldLine 1e-3 start (LineOnto (Segment (AtSheet (5 / 8) 0) (AtSheet 1 (3 / 4))) (Segment (AtSheet (3 / 8) 0) (AtSheet 0 (3 / 4))) (Just (CornerOf SouthWest))) of
        Left (NearestDisagrees _ taken OnlyOnPaper pointed) -> do
          (candidateOnPaper taken, candidateOnPaper pointed) `shouldBe` (True, False)
          candidateAlong taken `shouldSatisfy` near (V2 0 1)
          candidateThrough pointed `shouldSatisfy` near (V2 0.5 (-0.25))
        other -> expectationFailure ("expected nearest refused as pointing off the paper, got " <> show other)

    -- Read although one answer is all there is, nearest P has to name a
    -- place on the paper: two lines meeting at corner south-east leave only
    -- the diagonal, and a P off the paper is refused, not passed over. Turns
    -- red if nearest were resolved only when the rules needed it.
    it "refuses a nearest P off the paper even where it is not needed" $
      foldLine 1e-3 start (LineOnto (EdgeOf South) (EdgeOf East) (Just (AtSheet 2 2))) `shouldBe` Left (OffThePaper (V2 2 2))

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

  -- perpendicular to L through P, Huzita-Hatori's fourth construction.
  describe "draws a line through a point at right angles to a line" $ do
    -- After the first fold, corner south-east lies on the centre, and edge
    -- north has not moved, so the line is x = 1/2. Turns red if P were taken
    -- where it lay on the sheet, (1, 0), giving x = 1.
    it "through where the point is now" $ do
      FoldLine p d <- right (foldLine 1e-3 afterFirst (PerpendicularThrough (EdgeOf North) (CornerOf SouthEast)))
      onLine p d (V2 0.5 0) `shouldBe` True
      onLine p d (V2 0.5 1) `shouldBe` True

    -- After the first fold, [corner south-east, corner north-east] runs from
    -- the centre, where corner south-east now lies, to (1, 1), so the line
    -- across it through the centre is x + y = 1. Turns red if L were taken
    -- where it lay, along x = 1, giving y = 1/2.
    it "across the line where it lies now" $ do
      FoldLine p d <- right (foldLine 1e-3 afterFirst (PerpendicularThrough (Segment (CornerOf SouthEast) (CornerOf NorthEast)) Centre))
      onLine p d (V2 0 1) `shouldBe` True
      onLine p d (V2 1 0) `shouldBe` True

    -- L may be another construction, and P may lie on it: corner south-west
    -- to corner north-east folds along x + y = 1, which runs through the
    -- centre, and the line at right angles to it there is the diagonal y = x.
    it "across a point laid onto a point, through a point on that line" $ do
      FoldLine p d <- right (foldLine 1e-3 start (PerpendicularThrough (Onto (CornerOf SouthWest) (CornerOf NorthEast)) Centre))
      onLine p d (V2 0 0) `shouldBe` True
      onLine p d (V2 1 1) `shouldBe` True

    -- The midlines cross at the centre, so laying one onto the other has two
    -- answers, the diagonals, and needs a nearest. Written inside L, nearest
    -- (3/4, 3/4) chooses y = x as L, and the line at right angles to it
    -- through (1/4, 1/4) is x + y = 1/2: the nearest chooses L, not the fold.
    it "across the answer a nearest inside L chooses" $ do
      let midlines = LineOnto (Segment (MidpointOfEdge West) (MidpointOfEdge East)) (Segment (MidpointOfEdge South) (MidpointOfEdge North)) (Just (AtSheet (3 / 4) (3 / 4)))
      FoldLine p d <- right (foldLine 1e-3 start (PerpendicularThrough midlines (AtSheet (1 / 4) (1 / 4))))
      onLine p d (V2 0.5 0) `shouldBe` True
      onLine p d (V2 0 0.5) `shouldBe` True

    -- Owner decision 43's line on the folded crane, the root of the wing
    -- that M4's sequence folds. The crane is folded by its file's own
    -- angles, since a run cannot start folded yet. Corner north-west and the
    -- midpoint of edge north fold to (1, 0) and (1, 1/2), so L runs up
    -- x = 1, and corner north-east, the tip of the head, folds to the root's
    -- height, which in exact arithmetic is 1 - (sqrt 2 / 4)(1 + 2 sin 22.5
    -- degrees) (decisions C102); the file's coordinates put it within 2e-14
    -- of that. The root runs from x = 0.87585 to 1.12415
    -- (docs/notes/flap-roots.md).
    it "names the crane wing's root from two corners and the midpoint of edge north" $ do
      crane <- loadFoldFile "examples/crane.fold" >>= right
      folded <- flatOf (keyFrame crane)
      FoldLine p d <- right (foldLine 1e-3 folded (PerpendicularThrough (Segment (CornerOf NorthWest) (MidpointOfEdge North)) (CornerOf NorthEast)))
      let root = 1 - (sqrt 2 / 4) * (1 + 2 * sin (pi / 8))
      onLine p d (V2 0.87585 root) `shouldBe` True
      onLine p d (V2 1.12415 root) `shouldBe` True

    -- A run finds a hinge standing alone itself, from its earlier records,
    -- so this function meets one only inside another line.
    it "and refuses a hinge for L, a point off the paper, and an L whose two points are one" $ do
      foldLine 1e-3 start (PerpendicularThrough (HingeOf (Name "c1")) Centre) `shouldBe` Left (NotRunYet "\"hinge of NAME\" inside another line")
      foldLine 1e-3 start (PerpendicularThrough (EdgeOf South) (AtSheet 2 2)) `shouldBe` Left (OffThePaper (V2 2 2))
      foldLine 1e-3 start (PerpendicularThrough (Onto Centre Centre) Centre) `shouldBe` Left DegenerateConstruction

  -- An L is one face that is not convex. A line from its east edge rising
  -- westward leaves the long arm through its top, passes over the notch,
  -- and crosses the short arm's corner: two stretches of one face, which do
  -- not meet and stay two creases. Turns red if the stretch over the notch
  -- were kept, or the two were joined across it.
  describe "the stretches a line crosses with no crease" $
    it "takes each stretch inside a face that is not convex, and joins none across a gap" $ do
      let l = [[0, 0], [3, 0], [3, 0.5], [0.5, 0.5], [0.5, 0.7], [0, 0.7]]
          sheet = squareSheet {keyFrame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}}
          direction = V2 (-1.75) 0.35
          line = FoldLine (V2 3 0.15) ((1 / norm direction) *^ direction)
      st <- right (sheetState sheet) >>= flatOf . workingPattern
      crossedFaces st line `shouldBe` [FaceId 0]
      case chordsAcross st line [FaceId 0] of
        [(a, b), (c, d)] -> all (uncurry near) [(a, V2 3 0.15), (b, V2 1.25 0.5), (c, V2 0.5 0.65), (d, V2 0.25 0.7)] `shouldBe` True
        other -> expectationFailure ("expected two stretches, got " <> show other)

  -- A hinge's edges join into one stretch only where they meet end to end
  -- along one line on the sheet. On the accordion's bottom side: two
  -- quarters that meet join; two with a gap between stay apart; and a
  -- quarter and the crease standing on its end meet at a right angle and
  -- stay apart. Turns red if joining asked only that edges meet, or only
  -- that they lie on one line.
  it "joins a hinge's edges into stretches only where they meet along one line" $ do
    accordion <- loadFoldFile "examples/accordion.fold" >>= right
    paper <- workingPattern <$> right (sheetState accordion)
    st <- flatOf paper
    let at v = case drop v (verticesCoords paper) of
          (x : y : _) : _ -> V2 x y
          _ -> V2 (-1) (-1)
        edgeFrom p q = [EdgeId e | (e, (VertexId a, VertexId b)) <- zip [0 ..] (edgesVertices paper), (near (at a) p && near (at b) q) || (near (at a) q && near (at b) p)]
        stretchesOf pieces = length (hingeStretches st (concat pieces))
        first' = edgeFrom (V2 0 0) (V2 0.25 0)
    map length [first', edgeFrom (V2 0.25 0) (V2 0.5 0), edgeFrom (V2 0.5 0) (V2 0.75 0), edgeFrom (V2 0.25 0) (V2 0.25 1)] `shouldBe` [1, 1, 1, 1]
    stretchesOf [first', edgeFrom (V2 0.25 0) (V2 0.5 0)] `shouldBe` 1
    stretchesOf [first', edgeFrom (V2 0.5 0) (V2 0.75 0)] `shouldBe` 2
    stretchesOf [first', edgeFrom (V2 0.25 0) (V2 0.25 1)] `shouldBe` 2

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
