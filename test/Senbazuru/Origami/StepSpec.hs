-- |
-- Tests for working out what a step of a diagram does.
--
-- The thing worth pinning hardest is that the answer is derived and not
-- assumed: swap the two frames and the motion has to reverse, because nothing
-- in the code knows which way a fold "usually" goes.
module Senbazuru.Origami.StepSpec (spec) where

import Data.ByteString qualified as BS
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    FaceId (..),
    Frame (..),
    VertexId (..),
    allFrames,
    emptyFrame,
  )
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Step
import Test.Hspec

steps :: IO [Frame]
steps = do
  bytes <- BS.readFile "test/fixtures/quarter-fold-steps.fold"
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (allFrames f)

-- | Two square flaps either side of a square that does not move, joined only
-- through it: the shape of "fold both wings at once".
--
-- Faces 0 and 2 are the flaps and face 1 is the middle. Frames differ only in
-- where the flaps are.
twoFlaps :: [[Double]] -> Frame
twoFlaps coords =
  emptyFrame
    { verticesCoords = coords,
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 2, VertexId 3),
          (VertexId 4, VertexId 5)
        ],
      edgesAssignment = [Valley, Valley, Valley],
      facesVertices =
        [ map VertexId [0, 1, 3, 2],
          map VertexId [2, 3, 5, 4],
          map VertexId [4, 5, 7, 6]
        ]
    }

flapsApart, flapsFolded :: Frame
flapsApart =
  twoFlaps [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0], [3, 1]]
-- Both outer squares folded in on top of the middle one.
flapsFolded =
  twoFlaps [[2, 0], [2, 1], [1, 0], [1, 1], [2, 0], [2, 1], [1, 0], [1, 1]]

spec :: Spec
spec = do
  describe "the folding sequence fixture" $ do
    it "sees the left half swing onto the right" $ do
      fs <- steps
      motionsBetween (head fs) (fs !! 1)
        `shouldBe` Right
          [ Motion
              { motionFaces = [FaceId 2, FaceId 3],
                motionCreases = [EdgeId 8, EdgeId 10],
                motionFrom = V3 0.25 0.5 0,
                motionTo = V3 0.75 0.5 0
              }
          ]

    it "sees the top half fold down on the next step" $ do
      fs <- steps
      fmap (map (\m -> (motionFaces m, motionFrom m, motionTo m))) (motionsBetween (fs !! 1) (fs !! 2))
        `shouldBe` Right [([FaceId 1, FaceId 2], V3 0.75 0.75 0, V3 0.75 0.25 0)]

    it "reverses when the frames are given the other way round" $ do
      -- The direction is subtracted from the two frames, not assumed. Nothing
      -- here knows which way a fold "usually" goes, and this is what says so.
      fs <- steps
      let forwards = motionsBetween (head fs) (fs !! 1)
          backwards = motionsBetween (fs !! 1) (head fs)
      fmap (map motionFrom) backwards `shouldBe` fmap (map motionTo) forwards
      fmap (map motionTo) backwards `shouldBe` fmap (map motionFrom) forwards

    it "finds nothing between a frame and itself" $ do
      fs <- steps
      motionsBetween (head fs) (head fs) `shouldBe` Right []

  describe "several things moving at once" $ do
    it "gives each connected group its own motion" $ do
      -- Two flaps folding inwards. One arrow between them would point at the
      -- middle, where no paper goes.
      let got = fmap (map (\m -> (motionFaces m, motionFrom m, motionTo m))) (motionsBetween flapsApart flapsFolded)
      got
        `shouldBe` Right
          [ ([FaceId 0], V3 0.5 0.5 0, V3 1.5 0.5 0),
            ([FaceId 2], V3 2.5 0.5 0, V3 1.5 0.5 0)
          ]

    it "keeps paper that moves together in one group" $ do
      -- The two faces of the fixture's left half share an edge, so they are one
      -- flap and get one arrow, not two.
      fs <- steps
      fmap (map (length . motionFaces)) (motionsBetween (head fs) (fs !! 1))
        `shouldBe` Right [2]

  describe "what it will not compare" $ do
    it "refuses two frames that are not the same model" $ do
      let smaller = flapsApart {facesVertices = take 2 (facesVertices flapsApart)}
      motionsBetween flapsApart smaller
        `shouldBe` Left (FramesDiffer "faces_vertices" 3 2)

    it "refuses two frames whose faces are joined up differently" $ do
      -- Same count, different paper. Matching face i to face i across them would
      -- take the centre of one flap and the centre of an unrelated one as the
      -- two ends of a motion, and draw an arrow between them.
      let shuffled = flapsApart {facesVertices = reverse (facesVertices flapsApart)}
      motionsBetween flapsApart shuffled
        `shouldBe` Left (FramesDisagree "faces_vertices" 0)

    it "still finds the motion when neither frame records a fold angle" $ do
      -- Positions are what the reader is looking at. A frame may record no
      -- angles at all, and the paper has still moved.
      fmap (map motionCreases) (motionsBetween flapsApart flapsFolded)
        `shouldBe` Right [[], []]
