-- |
-- Tests for drawing a crease on a sheet.
--
-- Adding the segment is the easy half and barely appears here. What these
-- assert is the other half: which vertex the crease joined rather than
-- duplicated, what got cut on the way, and which of the file's own claims
-- stopped being true the moment the line was drawn.
--
-- The refusals matter as much as the successes, because the interesting ones
-- are not about the crease at all. A crease running off the edge of the paper
-- is refused by the face tracing, for a reason about the /paper/ — there is no
-- face to trace round a crease that stops in the middle of it — and that is
-- the answer this module deliberately leans on rather than asking a
-- \"is this point on the sheet\" question of its own.
module Senbazuru.Fold.CreasingSpec (spec) where

import Data.ByteString qualified as BS
import Senbazuru.Fold.Creasing
import Senbazuru.Fold.Load (decodeFile, renderLoadError)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Test.Hspec

-- | Load a fixture's key frame, in whatever format it is in.
fixture :: FilePath -> IO Frame
fixture name = do
  let path = "test/fixtures/" <> name
  bytes <- BS.readFile path
  case decodeFile path bytes of
    Left err -> fail (show (renderLoadError err))
    Right f -> pure (keyFrame f)

-- | A crease pattern with the given creases and nothing else recorded.
sheet :: [[Double]] -> [(Int, Int)] -> Frame
sheet points es =
  emptyFrame
    { frameClasses = ["creasePattern"],
      verticesCoords = points,
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- es]
    }

-- | The unit square, as four corners and four sides.
square :: Frame
square = sheet [[0, 0], [1, 0], [1, 1], [0, 1]] [(0, 1), (1, 2), (2, 3), (3, 0)]

-- | A frame's creases as plain pairs.
creasesOf :: Frame -> [(Int, Int)]
creasesOf fr = [(a, b) | (VertexId a, VertexId b) <- edgesVertices fr]

spec :: Spec
spec = do
  describe "where a crease's ends go" $ do
    it "joins a corner the paper already has, rather than adding a second one" $ do
      -- Appending a vertex at a place the sheet already has one leaves the
      -- crease hanging off a point joined to nothing, and the face tracing
      -- refuses it -- correctly, which is why this is worth pinning: the bug
      -- shows up as a refusal about the wrong thing.
      case creaseAlong (V2 0 0) (V2 1 1) Valley square of
        Left err -> expectationFailure (show err)
        Right s -> do
          verticesCoords s `shouldBe` verticesCoords square
          creasesOf s `shouldBe` [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2)]

    it "adds a vertex where an end lands in the middle of a side, and cuts it" $ do
      case creaseAlong (V2 0.5 0) (V2 0.5 1) Mountain square of
        Left err -> expectationFailure (show err)
        Right s -> do
          drop 4 (verticesCoords s) `shouldBe` [[0.5, 0], [0.5, 1]]
          -- Both sides the crease lands on are cut at it, and the new crease
          -- runs between the two new corners.
          creasesOf s
            `shouldBe` [(0, 4), (4, 1), (1, 2), (2, 5), (5, 3), (3, 0), (4, 5)]

    it "numbers the second end correctly when only the first joins a corner" $ do
      -- The off-by-one this had: numbering the ends 0 and 1 up front is wrong
      -- exactly when one lands on a corner and the other does not, which is
      -- the commonest crease there is.
      case creaseAlong (V2 0 0) (V2 1 0.5) Valley square of
        Left err -> expectationFailure (show err)
        Right s -> do
          drop 4 (verticesCoords s) `shouldBe` [[1, 0.5]]
          creasesOf s `shouldBe` [(0, 1), (1, 4), (4, 2), (2, 3), (3, 0), (0, 4)]

    it "is cut wherever it crosses a crease already there" $ do
      -- The diagonal of the quarter fold passes through its centre, which is
      -- already a vertex, so the new crease arrives as two pieces.
      fr <- fixture "quarter-fold.fold"
      case creaseAlong (V2 0 0) (V2 1 1) Valley fr of
        Left err -> expectationFailure (show err)
        Right s -> do
          length (verticesCoords s) `shouldBe` 9
          length (edgesVertices s) `shouldBe` 14
          length (facesVertices s) `shouldBe` 6

  describe "what the new crease carries" $ do
    it "gives every piece of it the assignment it was drawn with" $ do
      fr <- fixture "quarter-fold.fold"
      fmap (drop 12 . edgesAssignment) (creaseAlong (V2 0 0) (V2 1 1) Valley fr)
        `shouldBe` Right [Valley, Valley]

    it "gains a fold angle only where the file recorded them" $ do
      -- Present: the crease is drawn and not yet folded, so nought. Absent:
      -- still absent, which is what lets foldFrame read the angle off the
      -- assignment instead -- so "crease it" and "crease it and fold it" stay
      -- one decision the file makes rather than two this makes for it.
      fr <- fixture "quarter-fold.fold"
      fmap (drop 12 . edgesFoldAngle) (creaseAlong (V2 0 0) (V2 1 1) Valley fr)
        `shouldBe` Right [0, 0]
      fmap edgesFoldAngle (creaseAlong (V2 0 0) (V2 1 1) Valley square)
        `shouldBe` Right []

    it "puts the crease on the sheet's own plane, not on z = 0" $ do
      let raised = sheet [[0, 0, 5], [1, 0, 5], [1, 1, 5], [0, 1, 5]] [(0, 1), (1, 2), (2, 3), (3, 0)]
      fmap verticesCoords (creaseAlong (V2 0.5 0) (V2 0.5 1) Valley raised)
        `shouldBe` Right (verticesCoords raised <> [[0.5, 0, 5], [0.5, 1, 5]])

  describe "what drawing a crease invalidates" $
    it "re-derives the faces and drops the keys it cannot vouch for" $ do
      -- The line cuts at least one face in two, so every face the file
      -- recorded is wrong the moment it is drawn, and so is anything in
      -- frameExtras that indexes a face or an edge.
      fr <- fixture "quarter-fold.fold"
      case creaseAlong (V2 0 0) (V2 1 1) Valley fr of
        Left err -> expectationFailure (show err)
        Right s -> do
          facesVertices s `shouldNotBe` facesVertices fr
          length (facesVertices s) `shouldBe` 6
          frameExtras s `shouldBe` mempty

  describe "creases it will not draw" $ do
    it "refuses one with no length, which names no line to fold about" $
      creaseAlong (V2 0.5 0.5) (V2 0.5 0.5) Valley square
        `shouldBe` Left (EdgeWithoutLength (EdgeId 4))

    it "refuses one that runs off the edge of the paper" $ do
      -- Not checked as such: the crease simply ends at a vertex with one
      -- crease at it, and there is no face to trace round that. The refusal is
      -- about the paper rather than about the intent, which is the trade this
      -- module makes on purpose.
      creaseAlong (V2 0.5 0.5) (V2 3 3) Valley square
        `shouldBe` Left (VertexTooFewCreases (VertexId 4) 1)

    it "refuses to crease a folded form" $ do
      -- Creasing one means creasing through its layers, which is a different
      -- and much harder move: the line has to be cut into one crease per
      -- layer, and where those land on the flat sheet depends on the fold.
      fr <- fixture "simple.fold"
      creaseAlong (V2 0 0) (V2 1 1) Valley fr `shouldBe` Left SheetIsFolded

    it "refuses one drawn exactly on top of a crease already there" $
      -- End for end on an existing crease: nothing crosses, so nothing is cut,
      -- and what comes out is two creases between one pair of corners. That is
      -- the repeated edge Senbazuru.Fold.Faces refuses -- and it names the two
      -- creases the file has, which is the reason cutting leaves this case to
      -- it rather than reporting it itself.
      creaseAlong (V2 0 0) (V2 1 0) Valley square
        `shouldBe` Left (EdgeRepeated (EdgeId 0) (EdgeId 4))

    it "refuses one drawn along part of a crease already there" $
      -- The other shape of the same mistake, and the one cutting does have to
      -- catch: the new crease covers half the bottom edge, so that edge is cut
      -- at its far end and one of the pieces comes out doubled. Along the
      -- stretch the two share there are two answers to how the paper folds,
      -- and picking one is not senbazuru's to do.
      creaseAlong (V2 0 0) (V2 0.5 0) Valley square
        `shouldBe` Left (EdgesOverlap (EdgeId 0) (EdgeId 4))
