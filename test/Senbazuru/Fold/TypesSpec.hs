-- |
-- Decoding and encoding tests for the FOLD format, plus the refinement step in
-- "Senbazuru.Fold.Query".
--
-- Most cases here were chosen by looking at real @.fold@ files rather than at
-- the specification, because the things that actually break a decoder —
-- a fractional @file_spec@, vendor-prefixed keys, absent optional arrays — are
-- things the spec permits but does not draw attention to.
--
-- The encoding half is tested three ways, because each catches a different
-- mistake. Byte-for-byte examples pin the small decisions — key order, what
-- is left out — where a golden file would be overkill. A round trip over
-- every fixture is the criterion the format itself suggests: whatever a real
-- file says, saying it again must not change it. And a round trip over
-- generated documents is the only one that fails when someone adds a field to
-- 'Frame' and forgets the encoder, because 'genFrame' is written positionally
-- and stops compiling until they deal with it.
module Senbazuru.Fold.TypesSpec (spec) where

import Data.Aeson (Object, Value (..), eitherDecodeStrict', toJSON)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Foldable (for_)
import Data.List (isSuffixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Load (decodeFoldFile, encodeFoldFile)
import Senbazuru.Fold.Query
import Senbazuru.Fold.Types
import Senbazuru.Geometry.V3 (V3 (..))
import System.Directory (listDirectory)
import System.FilePath ((</>))
import Test.Hspec
import Test.QuickCheck

-- | Decode or fail the test with the decoder's own message.
decodeOrFail :: ByteString -> IO FoldFile
decodeOrFail bytes = case decodeFoldFile bytes of
  Left err -> fail ("decode failed: " <> err)
  Right f -> pure f

-- | Decode a lone frame, as a @file_frames@ entry is decoded: claiming no
-- file-level keys, so anything at all can land in 'frameExtras'.
decodeFrameOrFail :: ByteString -> IO Frame
decodeFrameOrFail bytes = case eitherDecodeStrict' bytes of
  Left err -> fail ("decode failed: " <> err)
  Right fr -> pure fr

-- | A document with nothing in it, to hang one frame off.
emptyFile :: FoldFile
emptyFile =
  FoldFile
    { fileSpec = Nothing,
      fileCreator = Nothing,
      fileAuthor = Nothing,
      fileTitle = Nothing,
      fileDescription = Nothing,
      fileClasses = [],
      keyFrame = emptyFrame,
      otherFrames = []
    }

-- | Decode as a bare JSON object, for the tests that ask which /keys/ came
-- out rather than what they meant.
decodeObjectOrFail :: ByteString -> IO Object
decodeObjectOrFail bytes = case eitherDecodeStrict' bytes of
  Left err -> fail ("decode failed: " <> err)
  Right o -> pure o

-- | Byte-for-byte copies of the @examples@ directory. The tests read these
-- rather than those because they are what the cabal file ships in a source
-- distribution.
fixtureDir :: FilePath
fixtureDir = "test" </> "fixtures"

-- | A frame with the given vertices and edges, everything else defaulted.
frameOf :: [[Double]] -> [(Int, Int)] -> [Assignment] -> Frame
frameOf vs es as =
  emptyFrame
    { verticesCoords = vs,
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- es],
      edgesAssignment = as
    }

-- | Keep generated documents small: a shrunk counterexample has to be
-- readable, and nothing here gets better at ten thousand vertices.
small :: Gen a -> Gen a
small = scale (`min` 6)

genText :: Gen Text
genText = T.pack <$> arbitrary

genMaybeText :: Gen (Maybe Text)
genMaybeText = oneof [pure Nothing, Just <$> genText]

-- | Keys the decoder does not understand, and values of the shapes a vendor
-- extension really uses.
--
-- Every key is namespaced, which is what the specification asks of a vendor
-- and also what keeps the generator inside the property's domain. The round
-- trip holds for frames the decoder could have produced, and the decoder can
-- never put a key it understands into 'frameExtras'. A generated
-- @vertices_coords@ would be a frame no file can produce, and the encoder
-- drops such an extra in favour of the field, so the round trip would fail on
-- an input it never promised to handle. That case is covered by the two
-- shadowing examples in "encoding" instead, which assert what actually matters
-- about it: the key comes out once.
genExtras :: Gen Object
genExtras = KM.fromList <$> small (listOf ((,) <$> genKey <*> genValue))
  where
    genKey = Key.fromText . ("x:" <>) <$> genText
    genValue =
      oneof
        [ toJSON <$> genText,
          toJSON <$> (arbitrary :: Gen Int),
          toJSON <$> (arbitrary :: Gen Bool),
          pure Null,
          toJSON <$> (arbitrary :: Gen [Int])
        ]

-- | An arbitrary frame, with no attempt to make it a sensible one.
--
-- The parallel arrays are generated independently, so their lengths disagree
-- constantly. That is the point: "Senbazuru.Fold.Types" is permissive by
-- design and has to write back whatever it was given, and the checking lives
-- in "Senbazuru.Fold.Query".
--
-- Written as a positional chain of '<*>' rather than with field names on
-- purpose. Adding a field to 'Frame' breaks this line, and breaking this line
-- is the only warning anyone gets that the encoder needs a new one too.
genFrame :: Gen Frame
genFrame =
  Frame
    <$> genMaybeText
    <*> genMaybeText
    <*> genMaybeText
    <*> small (listOf genText)
    <*> small (listOf genText)
    <*> genMaybeText
    <*> arbitrary
    <*> arbitrary
    <*> small (listOf (small (listOf arbitrary)))
    <*> small (listOf ((,) <$> genVertexId <*> genVertexId))
    <*> small (listOf (elements [minBound .. maxBound]))
    <*> small (listOf arbitrary)
    <*> small (listOf (small (listOf genVertexId)))
    <*> small (listOf genFaceOrder)
    <*> genExtras
  where
    genVertexId = VertexId <$> arbitrary
    genFaceId = FaceId <$> arbitrary
    genFaceOrder =
      FaceOrder <$> genFaceId <*> genFaceId <*> elements [minBound .. maxBound]

genFile :: Gen FoldFile
genFile =
  FoldFile
    <$> oneof [pure Nothing, Just <$> arbitrary]
    <*> genMaybeText
    <*> genMaybeText
    <*> genMaybeText
    <*> genMaybeText
    <*> small (listOf genText)
    <*> genFrame
    <*> small (listOf genFrame)

-- | A document with every key the encoder knows how to write set to something,
-- so that the set of keys it produces can be compared against 'fileKeys' and
-- 'frameKeys'.
--
-- Every field has to be non-default, since the encoder leaves defaults out.
saturated :: FoldFile
saturated =
  FoldFile
    { fileSpec = Just 1.2,
      fileCreator = Just "senbazuru",
      fileAuthor = Just "author",
      fileTitle = Just "title",
      fileDescription = Just "description",
      fileClasses = ["singleModel"],
      keyFrame =
        emptyFrame
          { frameAuthor = Just "author",
            frameTitle = Just "title",
            frameDescription = Just "description",
            frameClasses = ["creasePattern"],
            frameAttributes = ["2D"],
            frameUnit = Just "unit",
            frameParent = Just 0,
            frameInherit = True,
            verticesCoords = [[0, 0], [1, 0], [1, 1]],
            edgesVertices = [(VertexId 0, VertexId 1)],
            edgesAssignment = [Border],
            edgesFoldAngle = [0],
            facesVertices = [map VertexId [0, 1, 2]],
            faceOrders = [FaceOrder (FaceId 0) (FaceId 1) Above]
          },
      otherFrames = [emptyFrame {frameTitle = Just "second"}]
    }

spec :: Spec
spec = do
  fixtures <- runIO (sort . filter (".fold" `isSuffixOf`) <$> listDirectory fixtureDir)

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

    it "reads past a vendor-prefixed key it does not understand" $ do
      -- Not interpreted, but not lost either: it is kept in frameExtras so
      -- that writing the file out again does not destroy it. See "encoding".
      f <- decodeOrFail "{\"cpedit:page\": {\"xMin\": 0}, \"file_title\": \"t\"}"
      fileTitle f `shouldBe` Just "t"
      KM.keys (frameExtras (keyFrame f)) `shouldBe` ["cpedit:page"]

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

  describe "faceOrders" $ do
    it "decodes the triple and its three signs" $ do
      f <- decodeOrFail "{\"faceOrders\": [[2, 0, -1], [1, 0, 1], [3, 0, 0]]}"
      faceOrders (keyFrame f)
        `shouldBe` [ FaceOrder (FaceId 2) (FaceId 0) Below,
                     FaceOrder (FaceId 1) (FaceId 0) Above,
                     FaceOrder (FaceId 3) (FaceId 0) Unordered
                   ]

    it "rejects a sign that is not -1, 0 or 1" $
      -- A decode failure has to mean "this is not FOLD", and 2 is not a value
      -- the specification allows.
      decodeFoldFile "{\"faceOrders\": [[0, 1, 2]]}" `shouldSatisfy` isLeft

    it "rejects an entry that is not a triple" $
      decodeFoldFile "{\"faceOrders\": [[0, 1]]}" `shouldSatisfy` isLeft

    it "reads simple.fold's stacking as the file states it" $ do
      -- Two faces recorded as lying below a third: the only fixture in the repo
      -- that carries an ordering at all.
      f <- decodeOrFail =<< BS.readFile "test/fixtures/simple.fold"
      faceOrders (keyFrame f)
        `shouldBe` [ FaceOrder (FaceId 2) (FaceId 0) Below,
                     FaceOrder (FaceId 3) (FaceId 0) Below
                   ]

  describe "frameFaceOrders" $ do
    it "passes an ordering whose faces all exist" $ do
      let fr = (frameOf [[0, 0]] [] []) {facesVertices = replicate 2 [], faceOrders = [FaceOrder (FaceId 0) (FaceId 1) Above]}
      fmap length (frameFaceOrders fr) `shouldBe` Right 1

    it "reports an ordering that names a face there is none of" $ do
      let fr = (frameOf [[0, 0]] [] []) {facesVertices = [[]], faceOrders = [FaceOrder (FaceId 0) (FaceId 4) Above]}
      frameFaceOrders fr `shouldBe` Left (FaceOrderOutOfRange (FaceId 4) 1)

    it "reports a face stacked against itself" $ do
      -- It says nothing, and is far likelier to be a typo than a claim.
      let fr = (frameOf [[0, 0]] [] []) {facesVertices = [[]], faceOrders = [FaceOrder (FaceId 0) (FaceId 0) Above]}
      frameFaceOrders fr `shouldBe` Left (FaceOrderSelf (FaceId 0))

  describe "frameFaces" $ do
    it "resolves a face to the points that bound it" $ do
      let fr = (frameOf [[0, 0], [1, 0], [1, 1]] [] []) {facesVertices = [map VertexId [0, 1, 2]]}
      fmap (map faceCorners) (frameFaces fr)
        `shouldBe` Right [[V3 0 0 0, V3 1 0 0, V3 1 1 0]]

    it "keeps the vertex ids beside the points" $ do
      -- Which faces share an edge is a question about ids, and recovering it
      -- from coordinates would mean comparing Doubles for equality.
      let fr = (frameOf [[0, 0], [1, 0], [1, 1]] [] []) {facesVertices = [map VertexId [2, 0, 1]]}
      fmap (map faceVertexIds) (frameFaces fr)
        `shouldBe` Right [map VertexId [2, 0, 1]]

    it "has no faces for a frame that records none, which is not an error" $
      -- faces_vertices is optional and plenty of real crease patterns omit it.
      frameFaces (frameOf [[0, 0], [1, 1]] [(0, 1)] [Valley]) `shouldBe` Right []

    it "reports which face refers to a vertex that does not exist" $ do
      let fr = (frameOf [[0, 0], [1, 0]] [] []) {facesVertices = [map VertexId [0, 1, 9]]}
      frameFaces fr `shouldBe` Left (FaceVertexOutOfRange (FaceId 0) (VertexId 9) 2)

    it "rejects a ring that closes itself explicitly" $ do
      -- FOLD closes the ring implicitly, so a repeated first corner is one
      -- corner listed twice. Harmless to a fill, but faceVertexIds is what a
      -- consumer pairs up into edges, and this would give it a self-loop.
      let fr = (frameOf [[0, 0], [1, 0], [1, 1]] [] []) {facesVertices = [map VertexId [0, 1, 2, 0]]}
      frameFaces fr `shouldBe` Left (FaceRingClosed (FaceId 0))

    it "rejects a closed ring before counting its corners" $ do
      -- [0, 1, 0] has three entries and encloses nothing. Checking the length
      -- first would let it through as a face.
      let fr = (frameOf [[0, 0], [1, 0]] [] []) {facesVertices = [map VertexId [0, 1, 0]]}
      frameFaces fr `shouldBe` Left (FaceRingClosed (FaceId 0))

    it "rejects a face with fewer than three corners" $ do
      -- Two corners enclose no paper. Skipping it quietly would draw a sheet
      -- with a hole in it and say nothing.
      let fr = (frameOf [[0, 0], [1, 0], [1, 1]] [] []) {facesVertices = [map VertexId [0, 1]]}
      frameFaces fr `shouldBe` Left (FaceTooFewCorners (FaceId 0) 2)

  describe "encoding" $ do
    it "writes nothing for a document that says nothing" $ do
      -- The whole of the "absent stays absent" rule in one line: {} decodes to
      -- a FoldFile of empty lists and Nothings, and none of them get written.
      f <- decodeOrFail "{}"
      encodeFoldFile f `shouldBe` "{}\n"

    it "writes the keys in the order the specification lists them" $ do
      -- Not cosmetic. It is what makes the output reproducible and a diff
      -- between two files readable, and a KeyMap has no order to inherit.
      f <-
        decodeOrFail
          "{\"faceOrders\": [[1, 0, -1]], \"frame_title\": \"f\",\
          \ \"vertices_coords\": [[0, 0]], \"file_title\": \"t\"}"
      encodeFoldFile f
        `shouldBe` "{\"file_title\":\"t\",\"frame_title\":\"f\",\
                   \\"vertices_coords\":[[0,0]],\"faceOrders\":[[1,0,-1]]}\n"

    it "leaves out an array the file did not have" $ do
      -- edges_assignment is absent, and the decoder reports it as []. Writing
      -- [] back would tell a reader this file records no assignments, which is
      -- a different claim from not mentioning them.
      f <- decodeOrFail "{\"edges_vertices\": [[0, 1]]}"
      encodeFoldFile f `shouldBe` "{\"edges_vertices\":[[0,1]]}\n"

    it "leaves out frame_inherit when it is false, which absence already means" $ do
      f <- decodeOrFail "{\"frame_inherit\": false}"
      encodeFoldFile f `shouldBe` "{}\n"

    it "writes an assignment as its uppercase code, whatever case it arrived in" $ do
      -- One of the two places the round trip is deliberately not the identity
      -- on bytes. A lowercase "m" is a tool being loose; the spec says M.
      f <- decodeOrFail "{\"edges_assignment\": [\"m\", \"v\"]}"
      encodeFoldFile f `shouldBe` "{\"edges_assignment\":[\"M\",\"V\"]}\n"

    it "writes a stacking back as the sign it was read from" $ do
      f <- decodeOrFail "{\"faceOrders\": [[2, 0, 1], [3, 0, -1], [4, 0, 0]]}"
      encodeFoldFile f
        `shouldBe` "{\"faceOrders\":[[2,0,1],[3,0,-1],[4,0,0]]}\n"

    it "keeps a key it does not understand, after the ones it does" $ do
      -- Both kinds: a vendor extension, and a part of the specification that
      -- is simply not implemented here.
      f <-
        decodeOrFail
          "{\"cpedit:page\": {\"xMin\": 0}, \"vertices_edges\": [[0, 1]],\
          \ \"file_title\": \"t\"}"
      encodeFoldFile f
        `shouldBe` "{\"file_title\":\"t\",\"cpedit:page\":{\"xMin\":0},\
                   \\"vertices_edges\":[[0,1]]}\n"

    it "puts an unknown top-level key back at the top level, not into a frame" $ do
      -- The top-level object is both the file and the key frame, so an unknown
      -- key there is filed under the key frame's extras. It has to come back
      -- out at the top -- with the rest of the key frame, so before
      -- file_frames -- and not be copied into the frames themselves.
      f <-
        decodeOrFail
          "{\"x:a\": 1, \"file_frames\": [{\"x:b\": 2}]}"
      encodeFoldFile f
        `shouldBe` "{\"x:a\":1,\"file_frames\":[{\"x:b\":2}]}\n"

    it "writes a key once when an extra shadows a field, preferring the field" $ do
      -- The decoder cannot build such a frame -- it subtracts the same keys --
      -- but a caller assembling one by hand can, and a JSON object with a
      -- repeated key is read differently by different tools: aeson takes the
      -- first, JavaScript's JSON.parse the last. A format written for
      -- interchange must not emit one.
      let shadowed =
            emptyFrame
              { frameTitle = Just "field",
                frameExtras = KM.fromList [("frame_title", String "extra")]
              }
      encodeFoldFile (emptyFile {keyFrame = shadowed})
        `shouldBe` "{\"frame_title\":\"field\"}\n"

    it "writes a file-level key once when the key frame carries it as an extra" $ do
      -- The same hazard one level up, and the reason framePairs takes the
      -- caller's claimed keys the way parseFrame does. Decoding a bare Frame
      -- claims nothing, so file_spec really does land in its extras -- and that
      -- frame can then be installed as a key frame.
      lone <- decodeFrameOrFail "{\"file_spec\": 1.1}"
      KM.keys (frameExtras lone) `shouldBe` ["file_spec"]
      encodeFoldFile (emptyFile {fileSpec = Just 1.1, keyFrame = lone})
        `shouldBe` "{\"file_spec\":1.1}\n"

    it "writes a negative zero as zero, the way the SVG backend does" $ do
      -- Folding produces negative zeros, and -0.0 == 0.0 is True while the two
      -- format differently -- the same trap formatNumber and the glTF export
      -- both have to dodge. Here it is dodged by going through Value: toJSON
      -- of a Double rounds through Scientific, which has no signed zero.
      -- encode (-0.0 :: Double) on its own is "-0.0", so building the Series
      -- straight from toEncoding would undo this. That is what this pins.
      encodeFoldFile (emptyFile {keyFrame = emptyFrame {verticesCoords = [[-0.0, 0]]}})
        `shouldBe` "{\"vertices_coords\":[[0,0]]}\n"

    it "does not mistake a file-level key for something it does not understand" $ do
      -- fileKeys is what stops the key frame collecting file_spec as an extra
      -- and the encoder then writing it twice.
      f <- decodeOrFail "{\"file_spec\": 1.1}"
      KM.keys (frameExtras (keyFrame f)) `shouldBe` []

  describe "the round trip" $ do
    for_ fixtures $ \name ->
      it ("is a fixed point on " <> name) $ do
        -- The criterion from the issue this was written for: whatever a real
        -- file says, decoding it, writing it and decoding it again must not
        -- have changed anything. The second half checks the bytes settle too,
        -- so the first pass is a normalisation and not an oscillation.
        original <- decodeOrFail =<< BS.readFile (fixtureDir </> name)
        again <- decodeOrFail (encodeFoldFile original)
        again `shouldBe` original
        encodeFoldFile again `shouldBe` encodeFoldFile original

    it "survives a document nobody would write" $
      -- Generated frames have parallel arrays of mismatched lengths, faces
      -- naming vertices that do not exist and vendor keys full of nulls. None
      -- of that is this layer's business to object to, and all of it has to
      -- come back unchanged.
      forAll genFile $ \f ->
        decodeFoldFile (encodeFoldFile f) === Right f

    it "writes every key it claims to know, and no others" $ do
      -- The other half. Encoding a document with every field set has to
      -- produce exactly the keys the two lists name.
      o <- decodeObjectOrFail (encodeFoldFile saturated)
      sort (KM.keys o) `shouldBe` sort (fileKeys <> frameKeys)
