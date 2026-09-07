-- |
-- Tests for turning a list of line segments into a FOLD frame.
--
-- Nothing here reads a file. The two readers have their own specs; what is
-- left is the part they share, which is where the interesting decisions are:
-- how close two endpoints have to be before they are one vertex, what happens
-- to the ones that are not, and which of a frame's keys the result is entitled
-- to claim.
--
-- The tolerance tests are written as pairs — one input just inside it and one
-- just outside — because a single \"these merged\" assertion also passes for a
-- reader that merges everything.
module Senbazuru.Import.SegmentsSpec (spec) where

import Senbazuru.Fold.Types (Assignment (..), FoldFile (..), Frame (..), VertexId (..), emptyFrame)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Import.Segments
import Test.Hspec

-- | A segment on the 400-unit square both editors draw on, which is the size
-- every tolerance below is relative to.
segment :: Int -> (Double, Double) -> (Double, Double) -> Segment
segment line (x1, y1) (x2, y2) =
  Segment
    { segLine = line,
      segStart = V2 x1 y1,
      segEnd = V2 x2 y2,
      segAssignment = Mountain
    }

-- | The paper's own diagonal, in the two segments that establish it. Every
-- test that talks about the tolerance includes these so that the number is the
-- same one 'mergeTolerance' would compute from a real file.
paper :: [Segment]
paper =
  [ segment 1 (-200, -200) (200, -200),
    segment 2 (200, 200) (-200, 200)
  ]

-- | The tolerance those two segments produce: a billionth of @400√2@.
paperTolerance :: Double
paperTolerance = mergeTolerance paper

spec :: Spec
spec = do
  describe "mergeTolerance" $ do
    it "is a billionth of the pattern's diagonal" $
      -- Stated as a range rather than recomputed, because computing it a
      -- second way here would only test that two float expressions agree.
      paperTolerance `shouldSatisfy` \t -> t > 5.6e-7 && t < 5.7e-7

    it "is zero for no segments at all" $
      mergeTolerance [] `shouldBe` 0

  describe "frameFromSegments" $ do
    it "merges endpoints closer together than the tolerance" $ do
      -- The paper is four corners. A crease starting nine tenths of a
      -- tolerance from one of them starts *at* it, so this is five vertices.
      let nudge = 0.9 * paperTolerance
          segments = paper <> [segment 3 (-200 + nudge, -200) (0, 0)]
      fmap (length . verticesCoords) (frameFromSegments segments) `shouldBe` Right 5

    it "keeps endpoints further apart than the tolerance" $ do
      -- The same crease, its start moved out past the tolerance: now it is a
      -- vertex of its own, and there are six.
      let nudge = 1.1 * paperTolerance
          segments = paper <> [segment 3 (-200 + nudge, -200) (0, 0)]
      fmap (length . verticesCoords) (frameFromSegments segments) `shouldBe` Right 6

    it "merges a pair that falls either side of a grid cell boundary" $ do
      -- The reason the grid searches nine cells and not one. These two points
      -- are half a tolerance apart, so they are the same vertex, but they sit
      -- on opposite sides of a multiple of the tolerance and so land in
      -- different cells. A reader that compared cells and stopped there would
      -- give eight vertices here rather than seven.
      let boundary = fromIntegral (ceiling (100 / paperTolerance) :: Integer) * paperTolerance
          -- Not `before`/`after`: hspec exports both, as hooks.
          under = boundary - 0.25 * paperTolerance
          over = boundary + 0.25 * paperTolerance
          segments = paper <> [segment 3 (under, 0) (0, 0), segment 4 (over, 0) (0, -100)]
      fmap (length . verticesCoords) (frameFromSegments segments) `shouldBe` Right 7

    it "numbers vertices in the order the file first mentions them" $ do
      let segments =
            [ segment 1 (10, 0) (20, 0),
              segment 2 (20, 0) (30, 0)
            ]
      fmap verticesCoords (frameFromSegments segments)
        `shouldBe` Right [[10, 0], [20, 0], [30, 0]]
      fmap edgesVertices (frameFromSegments segments)
        `shouldBe` Right
          [ (VertexId 0, VertexId 1),
            (VertexId 1, VertexId 2)
          ]

    it "keeps every segment's assignment, in file order" $ do
      let assigned a s = s {segAssignment = a}
          segments =
            [ assigned Border (segment 1 (0, 0) (1, 0)),
              assigned Valley (segment 2 (1, 0) (1, 1)),
              assigned Flat (segment 3 (1, 1) (0, 0))
            ]
      fmap edgesAssignment (frameFromSegments segments)
        `shouldBe` Right [Border, Valley, Flat]

    it "refuses a segment whose endpoints are the same point, naming its line" $
      frameFromSegments (paper <> [segment 17 (0, 0) (0, 0)])
        `shouldBe` Left (DegenerateSegment 17)

    it "refuses a segment shorter than the tolerance, which is the same thing" $ do
      let tiny = 0.5 * paperTolerance
      frameFromSegments (paper <> [segment 17 (0, 0) (tiny, 0)])
        `shouldBe` Left (DegenerateSegment 17)

    it "refuses a segment longer than the tolerance that still lands on one vertex" $ do
      -- Not the same question as the two above, which is the whole point. This
      -- segment is 1.8 tolerances long, so measuring it says it is a fine
      -- crease; but it straddles an existing vertex with each end within one
      -- tolerance of it, so both ends intern to that vertex and the edge would
      -- run from a vertex to itself. Judging the merged result rather than the
      -- segment is what catches it.
      let straddle = 0.9 * paperTolerance
          corner = (-200, -200)
          segments =
            paper
              <> [segment 17 (fst corner - straddle, snd corner) (fst corner + straddle, snd corner)]
      frameFromSegments segments `shouldBe` Left (DegenerateSegment 17)

    it "refuses a file with nothing in it" $
      frameFromSegments [] `shouldBe` Left EmptyPattern

    it "claims only what reading a segment list established" $ do
      -- A .cp or an .opx says the paper is flat and creased, and says nothing
      -- else. Absent is not empty here as much as it is in a FOLD file: an
      -- invented faces_vertices or edges_foldAngle would be written straight
      -- back out by saveFoldFile as though the file had said it.
      case frameFromSegments paper of
        Left err -> expectationFailure ("expected a frame, got " <> show err)
        Right frame -> do
          frameClasses frame `shouldBe` ["creasePattern"]
          frameAttributes frame `shouldBe` ["2D"]
          facesVertices frame `shouldBe` []
          edgesFoldAngle frame `shouldBe` []
          frameUnit frame `shouldBe` Nothing
          -- Everything else is still exactly emptyFrame, so a key added to
          -- Frame later cannot be filled in here without this noticing.
          frame
            { verticesCoords = [],
              edgesVertices = [],
              edgesAssignment = [],
              frameClasses = [],
              frameAttributes = []
            }
            `shouldBe` emptyFrame

  describe "foldFileFromSegments" $
    it "wraps the frame in a one-frame document and claims nothing more" $
      case foldFileFromSegments paper of
        Left err -> expectationFailure ("expected a document, got " <> show err)
        Right file -> do
          fileSpec file `shouldBe` Just 1.2
          fileClasses file `shouldBe` ["singleModel"]
          fileCreator file `shouldBe` Nothing
          fileTitle file `shouldBe` Nothing
          otherFrames file `shouldBe` []
          Right (keyFrame file) `shouldBe` frameFromSegments paper

  describe "fromScreenPoint" $ do
    it "turns a downward y into an upward one" $
      -- The one line of this module that changes the model rather than
      -- describing it. See its Haddock for why leaving it out is not a
      -- different convention but a different model.
      fromScreenPoint 3 4 `shouldBe` V2 3 (-4)

  describe "readNumber" $ do
    it "reads what Java's Double.toString writes" $ do
      readNumber "-200.0" `shouldBe` Just (-200.0)
      readNumber "2.4492935982947067E-14" `shouldBe` Just 2.4492935982947067e-14

    it "refuses a number with something stuck on the end" $
      -- The reason both readers go through this one function: TR.double is a
      -- reader combinator and stops at the first thing it does not
      -- understand, so a caller that ignores the remainder reads "1.0mm" as 1.
      readNumber "1.0mm" `shouldBe` Nothing
