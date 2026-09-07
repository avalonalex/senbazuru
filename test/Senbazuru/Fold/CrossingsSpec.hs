-- |
-- Tests for cutting creases where they meet.
--
-- The shape of this file follows the shape of the risk. Cutting is easy to get
-- /nearly/ right — the pieces come out, they look like creases, and the errors
-- are all in where the cuts landed and what the pieces inherited. So most of
-- these assert on exact vertices and exact creases rather than on counts.
--
-- The one case worth the most attention is three creases through one point,
-- which is what @unit-square.fold@ has. Taken pair by pair that is three
-- crossings, and a reader that adds each separately puts three vertices a
-- rounding error apart where there should be one. Counting vertices catches
-- that; counting faces does not, because the extra faces are slivers.
module Senbazuru.Fold.CrossingsSpec (spec) where

import Data.ByteString qualified as BS
import Senbazuru.Fold.Crossings
import Senbazuru.Fold.Faces (traceFaces)
import Senbazuru.Fold.Load (decodeFile, encodeFoldFile, renderLoadError)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
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

-- | The same, with an assignment and an angle on every crease.
creased :: [[Double]] -> [((Int, Int), Assignment, Double)] -> Frame
creased points es =
  (sheet points [e | (e, _, _) <- es])
    { edgesAssignment = [a | (_, a, _) <- es],
      edgesFoldAngle = [d | (_, _, d) <- es]
    }

-- | A frame's creases as plain pairs, for asserting on without newtype noise.
creasesOf :: Frame -> [(Int, Int)]
creasesOf fr = [(a, b) | (VertexId a, VertexId b) <- edgesVertices fr]

spec :: Spec
spec = do
  describe "a crossing" $ do
    it "becomes a vertex, and cuts both creases at it" $ do
      -- Two creases through the middle of a square, crossing at (0.5, 0.5).
      let crossed =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]]
              [(4, 5), (6, 7)]
      case splitCrossings crossed of
        Left err -> expectationFailure (show err)
        Right s -> do
          verticesCoords s `shouldBe` verticesCoords crossed <> [[0.5, 0.5]]
          creasesOf s `shouldBe` [(4, 8), (8, 5), (6, 8), (8, 7)]

    it "is one vertex when three creases pass through one place" $ do
      -- The case the design turns on. Pairwise there are three crossings here,
      -- and computing each on its own gives three points a rounding error
      -- apart -- three vertices where there should be one, joined by creases
      -- shorter than anything a person drew.
      fr <- fixture "unit-square.fold"
      case splitCrossings fr of
        Left err -> expectationFailure (show err)
        Right s -> do
          length (verticesCoords s) `shouldBe` 9
          drop 8 (verticesCoords s) `shouldBe` [[0.5, 0.5]]
          length (edgesVertices s) `shouldBe` 14

    it "cuts one crease at several places, in the order they come along it" $ do
      -- A crease crossed twice, which is the only case where the order of the
      -- cuts can be wrong. Out of order, the pieces run (0,7) (7,6) (6,1): a
      -- zigzag covering the same line three times, in which the first piece
      -- passes straight through vertex 6. Every count is still right, which is
      -- why this asserts on the creases themselves.
      let twice =
            sheet
              [[0, 0], [3, 0], [1, -1], [1, 1], [2, -1], [2, 1]]
              [(0, 1), (2, 3), (4, 5)]
      case splitCrossings twice of
        Left err -> expectationFailure (show err)
        Right s -> do
          drop 6 (verticesCoords s) `shouldBe` [[1, 0], [2, 0]]
          creasesOf s `shouldBe` [(0, 6), (6, 7), (7, 1), (2, 6), (6, 3), (4, 7), (7, 5)]

    it "leaves a pattern with nothing to cut exactly as it found it" $ do
      -- Byte for byte through the writer, not merely equal in the parts this
      -- module touches: a frame that needed no cutting must keep its faces and
      -- its unrecognised keys, which is what lets this sit in front of every
      -- fold without quietly stripping them.
      fr <- fixture "crane.fold"
      fmap (encodeFoldFile . asFile) (splitCrossings fr)
        `shouldBe` Right (encodeFoldFile (asFile fr))

    it "finds nothing left to cut the second time" $ do
      fr <- fixture "unit-square.fold"
      let once = splitCrossings fr
      (splitCrossings =<< once) `shouldBe` once

  describe "a vertex on a crease that does not end there" $
    it "cuts the crease at it, adding no vertex" $ do
      -- The T-junction, and the case a real ORIPA design turns out to be full
      -- of: the vertex is already in the file, so only the cutting is missing,
      -- and it is exact rather than computed.
      let tee =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0], [0.5, 0.5]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5)]
      case splitCrossings tee of
        Left err -> expectationFailure (show err)
        Right s -> do
          verticesCoords s `shouldBe` verticesCoords tee
          creasesOf s `shouldBe` [(0, 4), (4, 1), (1, 2), (2, 3), (3, 0), (4, 5)]

  describe "what a piece inherits" $ do
    it "keeps its parent's assignment and fold angle" $ do
      -- Cutting a valley in two does not make either half something else.
      let crossed =
            creased
              [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]]
              [((4, 5), Mountain, -180), ((6, 7), Valley, 180)]
      fmap edgesAssignment (splitCrossings crossed)
        `shouldBe` Right [Mountain, Mountain, Valley, Valley]
      fmap edgesFoldAngle (splitCrossings crossed)
        `shouldBe` Right [-180, -180, 180, 180]

    it "leaves an array the file did not have absent" $ do
      -- An assignment invented for a crease the file said nothing about would
      -- be a claim it never made.
      let bare =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]]
              [(4, 5), (6, 7)]
      fmap edgesAssignment (splitCrossings bare) `shouldBe` Right []
      fmap edgesFoldAngle (splitCrossings bare) `shouldBe` Right []

    it "refuses an array that does not line up, rather than reading past its end" $ do
      let short =
            (sheet [[0, 0], [1, 0], [1, 1]] [(0, 1), (1, 2), (2, 0)])
              { edgesAssignment = [Border]
              }
      splitCrossings short
        `shouldBe` Left (ArrayLengthMismatch "edges_vertices" 3 "edges_assignment" 1)

  describe "what cutting destroys" $
    it "drops the faces and the keys it cannot vouch for, but only when it cuts" $ do
      -- Preserve at the boundary, discard at the transform: cutting renumbers
      -- the vertices, so a faces_vertices written against the old numbering is
      -- no longer true of this frame and neither is anything in frameExtras
      -- that indexes one.
      fr <- fixture "unit-square.fold"
      let withFaces = fr {facesVertices = [map VertexId [0, 1, 2, 3]]}
      fmap facesVertices (splitCrossings withFaces) `shouldBe` Right []
      fmap frameExtras (splitCrossings withFaces) `shouldBe` Right mempty

  describe "drawings it leaves alone" $ do
    it "passes a folded form through untouched rather than cutting it" $ do
      -- A folded form's creases cross wherever the paper overlaps itself, and
      -- cutting there would be cutting the paper. Whether a folded form is
      -- acceptable at all is Senbazuru.Fold.Faces's call, not this module's --
      -- two places answering it is two places that can disagree.
      fr <- fixture "simple.fold"
      splitCrossings fr `shouldBe` Right fr

    it "passes a sheet with no creases through untouched" $
      splitCrossings (sheet [[0, 0], [1, 0]] []) `shouldBe` Right (sheet [[0, 0], [1, 0]] [])

  describe "the whole point of it" $
    it "turns unit-square.fold from six faces nobody could trace into six faces" $ do
      -- Before this module, that file was refused twice over: for recording no
      -- faces, and then for its creases crossing. Neither was a fact about the
      -- paper -- the crossing is on the sheet already, and only the vertex was
      -- missing.
      fr <- fixture "unit-square.fold"
      traceFaces fr `shouldBe` Left (EdgesCross (EdgeId 8) (EdgeId 9))
      fmap length (traceFaces =<< splitCrossings fr) `shouldBe` Right 6
  where
    -- The writer takes a document, so a frame has to be wrapped in one to be
    -- compared as bytes.
    asFile fr =
      FoldFile
        { fileSpec = Just 1.2,
          fileCreator = Nothing,
          fileAuthor = Nothing,
          fileTitle = Nothing,
          fileDescription = Nothing,
          fileClasses = [],
          keyFrame = fr,
          otherFrames = []
        }
