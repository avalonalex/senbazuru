-- |
-- Decoding tests for the FOLD format, plus the refinement step in
-- "Senbazuru.Fold.Query".
--
-- Most cases here were chosen by looking at real @.fold@ files rather than at
-- the specification, because the things that actually break a decoder —
-- a fractional @file_spec@, vendor-prefixed keys, absent optional arrays — are
-- things the spec permits but does not draw attention to.
module Senbazuru.Fold.TypesSpec (spec) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import Test.Hspec

-- | Decode or fail the test with the decoder's own message.
decodeOrFail :: ByteString -> IO FoldFile
decodeOrFail bytes = case decodeFoldFile bytes of
  Left err -> fail ("decode failed: " <> err)
  Right f -> pure f

-- | A frame with the given vertices and edges, everything else defaulted.
frameOf :: [[Double]] -> [(Int, Int)] -> [Assignment] -> Frame
frameOf vs es as =
  emptyFrame
    { verticesCoords = vs,
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- es],
      edgesAssignment = as
    }

spec :: Spec
spec = do
  describe "decoding" $ do
    it "reads the minimum viable FOLD document" $ do
      f <- decodeOrFail "{}"
      fileSpec f `shouldBe` Nothing
      verticesCoords (keyFrame f) `shouldBe` []

    it "accepts a fractional file_spec, as written by real tools" $ do
      -- The spec calls this a number, and diagonal-cp.fold really does say 1.1.
      -- Typing it as Int would reject a valid file.
      f <- decodeOrFail "{\"file_spec\": 1.1}"
      fileSpec f `shouldBe` Just 1.1

    it "ignores vendor-prefixed keys it does not understand" $ do
      f <- decodeOrFail "{\"cpedit:page\": {\"xMin\": 0}, \"file_title\": \"t\"}"
      fileTitle f `shouldBe` Just "t"

    it "treats the top-level object as the key frame" $ do
      -- The one genuinely surprising thing about FOLD: file metadata and the
      -- first frame's data share the top-level object.
      f <- decodeOrFail "{\"file_title\": \"file\", \"frame_title\": \"frame\"}"
      fileTitle f `shouldBe` Just "file"
      frameTitle (keyFrame f) `shouldBe` Just "frame"

    it "collects file_frames after the key frame" $ do
      f <- decodeOrFail "{\"frame_title\": \"a\", \"file_frames\": [{\"frame_title\": \"b\"}]}"
      map frameTitle (allFrames f) `shouldBe` [Just "a", Just "b"]

    it "rejects an edge that does not have exactly two endpoints" $
      -- The (VertexId, VertexId) tuple type buys this check for free.
      decodeFoldFile "{\"edges_vertices\": [[0, 1, 2]]}" `shouldSatisfy` isLeft

    it "rejects an unknown edge assignment" $
      decodeFoldFile "{\"edges_assignment\": [\"Z\"]}" `shouldSatisfy` isLeft

    it "accepts lowercase assignment codes, which some tools emit" $ do
      f <- decodeOrFail "{\"edges_assignment\": [\"m\", \"v\"]}"
      edgesAssignment (keyFrame f) `shouldBe` [Mountain, Valley]

  describe "the diagonal-cp.fold fixture" $ do
    it "decodes with the structure the file describes" $ do
      f <- decodeOrFail =<< BS.readFile "test/fixtures/diagonal-cp.fold"
      let fr = keyFrame f
      fileSpec f `shouldBe` Just 1.1
      frameClasses fr `shouldBe` ["creasePattern"]
      length (verticesCoords fr) `shouldBe` 4
      length (edgesVertices fr) `shouldBe` 5
      edgesAssignment fr `shouldBe` [Border, Border, Border, Border, Valley]
      length (facesVertices fr) `shouldBe` 2

  describe "frameVertices" $ do
    it "gives a 2D vertex z = 0, the plane a flat sheet lies in" $
      frameVertices (frameOf [[1, 2]] [] []) `shouldBe` Right [V3 1 2 0]

    it "keeps z when the file supplies it" $
      -- Query no longer projects. Flattening is the camera's job now.
      frameVertices (frameOf [[1, 2, 99]] [] []) `shouldBe` Right [V3 1 2 99]

    it "ignores components beyond the third" $
      frameVertices (frameOf [[1, 2, 3, 4]] [] []) `shouldBe` Right [V3 1 2 3]

    it "rejects a vertex with fewer than two coordinates" $
      frameVertices (frameOf [[1]] [] [])
        `shouldBe` Left (VertexCoordTooShort (VertexId 0) 1)

  describe "frameCreases" $ do
    it "resolves edges to their endpoints" $ do
      let fr = frameOf [[0, 0], [1, 1]] [(0, 1)] [Valley]
      fmap (map (\c -> (creaseStart c, creaseEnd c, creaseAssignment c))) (frameCreases fr)
        `shouldBe` Right [(V3 0 0 0, V3 1 1 0, Valley)]

    it "reports which edge refers to a vertex that does not exist" $ do
      let fr = frameOf [[0, 0]] [(0, 7)] [Valley]
      frameCreases fr
        `shouldBe` Left (VertexIndexOutOfRange (EdgeId 0) (VertexId 7) 1)

    it "defaults every crease to Unassigned when edges_assignment is absent" $ do
      -- Absent means "nothing is known", which is exactly what U means.
      let fr = frameOf [[0, 0], [1, 1]] [(0, 1)] []
      fmap (map creaseAssignment) (frameCreases fr) `shouldBe` Right [Unassigned]

    it "rejects an edges_assignment array of the wrong length" $ do
      -- Present but mismatched is a corrupt file, not a case to paper over.
      let fr = frameOf [[0, 0], [1, 1]] [(0, 1)] [Valley, Mountain]
      frameCreases fr
        `shouldBe` Left (ArrayLengthMismatch "edges_vertices" 1 "edges_assignment" 2)

    it "has no vertices to draw for an empty frame" $
      frameVertices emptyFrame `shouldBe` Right []
