-- |
-- Tests for the 3D export.
--
-- Three layers, tested separately. The container — magic, lengths, alignment —
-- is what a viewer checks before it reads a byte of geometry, so it gets exact
-- assertions. The geometry is read back out of our own output and compared
-- with the frame it came from, which is the one test that would catch an axis
-- swapped the wrong way or a layer lifted by the wrong amount. And the whole
-- file gets a golden, because "these exact bytes" is the contract a viewer
-- holds us to.
--
-- The reader in this file is deliberately naive: it walks the JSON with aeson
-- and pulls floats out of the binary chunk by hand. A real glTF loader would
-- be a dependency the test suite does not need, and would also hide the very
-- offsets and alignments these tests exist to pin.
module Senbazuru.Render.GltfSpec (spec) where

import Data.Aeson (Value (..), decodeStrict)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.List (nub, sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Word (Word32, Word8)
import GHC.Float (castWord32ToFloat)
import Senbazuru.Diagram (Colour (..))
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FoldFile (..),
    Frame (..),
    VertexId (..),
    emptyFrame,
  )
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Render.Gltf
import Test.Golden (goldenBytes)
import Test.Hspec

-- | The key frame of a fixture.
fixture :: FilePath -> IO Frame
fixture path = do
  bytes <- BS.readFile path
  either (fail . ("decode failed: " <>)) (pure . keyFrame) (decodeFoldFile bytes)

-- | A fixture folded along its own angles.
folded :: FilePath -> IO Frame
folded path = do
  fr <- fixture path
  either (fail . ("fold failed: " <>) . show) pure (foldFrame fr)

-- | Export, or fail the test saying why.
export :: Thickness -> Frame -> IO ByteString
export t fr = either (fail . ("export failed: " <>) . show) pure (renderGlb defaultBudget t fr)

-- | A binary glTF document taken apart: the header's declared total, the JSON
-- chunk parsed, and the binary chunk as bytes.
data Glb = Glb
  { glbTotal :: Int,
    glbJsonLength :: Int,
    glbBinLength :: Int,
    glbJson :: Value,
    glbBin :: ByteString
  }

parseGlb :: ByteString -> IO Glb
parseGlb bytes = do
  BS.take 4 bytes `shouldBe` "glTF"
  word32At 4 `shouldBe` 2
  BS.take 4 (BS.drop 16 bytes) `shouldBe` "JSON"
  let jsonLen = fromIntegral (word32At 12)
      binHeader = 20 + jsonLen
  BS.take 4 (BS.drop (binHeader + 4) bytes) `shouldBe` "BIN\0"
  let binLen = fromIntegral (word32At binHeader)
  json <- maybe (fail "the JSON chunk does not parse") pure (decodeStrict (BS.take jsonLen (BS.drop 20 bytes)))
  pure
    Glb
      { glbTotal = fromIntegral (word32At 8),
        glbJsonLength = jsonLen,
        glbBinLength = binLen,
        glbJson = json,
        glbBin = BS.take binLen (BS.drop (binHeader + 8) bytes)
      }
  where
    word32At :: Int -> Word32
    word32At i = le (BS.unpack (BS.take 4 (BS.drop i bytes)))
    le [a, b, c, d] =
      fromIntegral a
        .|. (fromIntegral b `shiftL` 8)
        .|. (fromIntegral c `shiftL` 16)
        .|. (fromIntegral d `shiftL` 24)
    le _ = 0

-- | Walk into a JSON value by field name.
at :: Text -> Value -> Value
at k (Object o) = fromMaybe Null (KM.lookup (Key.fromText k) o)
at _ _ = Null

-- | The elements of a JSON array, or nothing at all for anything else.
items :: Value -> [Value]
items (Array v) = toList v
items _ = []

-- | The n-th element of a JSON array.
nth :: Int -> Value -> Value
nth i v = case drop i (items v) of
  (x : _) -> x
  [] -> Null

asInt :: Value -> Int
asInt (Number n) = round n
asInt _ = -1

asDouble :: Value -> Double
asDouble (Number n) = realToFrac n
asDouble _ = 0 / 0

-- | The floats an accessor of VEC3s refers to, read straight out of the
-- binary chunk through its buffer view.
vec3s :: Glb -> Int -> [(Float, Float, Float)]
vec3s glb accessorIx = triples (map float32 (chunksOf 4 bytes))
  where
    accessor = nth accessorIx (at "accessors" (glbJson glb))
    view = nth (asInt (at "bufferView" accessor)) (at "bufferViews" (glbJson glb))
    bytes = BS.take (asInt (at "byteLength" view)) (BS.drop (asInt (at "byteOffset" view)) (glbBin glb))
    float32 ws = castWord32ToFloat (foldr (\w acc -> (acc `shiftL` 8) .|. fromIntegral w) 0 ws)
    triples (x : y : z : rest) = (x, y, z) : triples rest
    triples _ = []

-- | The indices an accessor of 16-bit scalars refers to, as triangles.
triangles :: Glb -> Int -> [(Int, Int, Int)]
triangles glb accessorIx = threes (map word16 (chunksOf 2 bytes))
  where
    accessor = nth accessorIx (at "accessors" (glbJson glb))
    view = nth (asInt (at "bufferView" accessor)) (at "bufferViews" (glbJson glb))
    bytes = BS.take (asInt (at "byteLength" view)) (BS.drop (asInt (at "byteOffset" view)) (glbBin glb))
    word16 [lo, hi] = fromIntegral lo .|. (fromIntegral hi `shiftL` 8)
    word16 _ = -1
    threes (a : b : c : rest) = (a, b, c) : threes rest
    threes _ = []

chunksOf :: Int -> ByteString -> [[Word8]]
chunksOf n bs
  | BS.null bs = []
  | otherwise = BS.unpack (BS.take n bs) : chunksOf n (BS.drop n bs)

-- | One concave quad, tilted out of the sheet. Planar — it lies in the plane
-- @z = x@ — so that the test is about convexity and not about a face that is
-- not flat, and in the air so that no layer solver sees it first.
concaveInTheAir :: Frame
concaveInTheAir =
  emptyFrame
    { frameClasses = ["foldedForm"],
      verticesCoords = [[0, 0, 0], [2, 0, 2], [0.5, 0.5, 0.5], [0, 2, 0]],
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 0)
        ],
      edgesAssignment = [Border, Border, Border, Border],
      facesVertices = [map VertexId [0, 1, 2, 3]]
    }

-- | A unit square as two triangles, declared nothing: a crease pattern.
flatSheet :: Frame
flatSheet =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 0),
          (VertexId 0, VertexId 2)
        ],
      edgesAssignment = [Border, Border, Border, Border, Valley],
      facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 2, 3]]
    }

spec :: Spec
spec = do
  describe "the container" $ do
    it "is a well-formed binary glTF document" $ do
      bytes <- folded "test/fixtures/quarter-fold.fold" >>= export DefaultThickness
      glb <- parseGlb bytes
      -- The header's declared length is the file's, and both chunks are
      -- padded to the four-byte boundary the specification requires -- the
      -- JSON one with spaces, which a parser skips, and the binary one with
      -- zeros, which nothing reads.
      glbTotal glb `shouldBe` BS.length bytes
      glbJsonLength glb `mod` 4 `shouldBe` 0
      glbBinLength glb `mod` 4 `shouldBe` 0
      glbTotal glb `shouldBe` 12 + 8 + glbJsonLength glb + 8 + glbBinLength glb

    it "is the same bytes every time" $ do
      -- Folding leaves noise in the last bits of coordinates that are really
      -- zero, and float32 keeps -0.0 distinct from 0.0. Rounding before packing
      -- is what makes two runs agree, and what makes the goldens below
      -- possible at all.
      fr <- folded "test/fixtures/crane.fold"
      a <- export DefaultThickness fr
      b <- export DefaultThickness fr
      a `shouldBe` b

  describe "the geometry" $ do
    it "lifts each layer of a flat model one thickness above the one below" $ do
      -- The quarter fold: four faces landing on one quadrant. Every face owns
      -- its four corners, so sixteen vertices, and the layer solver's order --
      -- bottom-left quadrant lowest -- becomes height. glTF is y-up, so the
      -- lift is in y.
      fr <- folded "test/fixtures/quarter-fold.fold"
      glb <- export DefaultThickness fr >>= parseGlb
      let ps = vec3s glb 0
          heights = [y | (_, y, _) <- ps]
          t = 0.0005 -- a thousandth of the folded model's span, which is 0.5
      length ps `shouldBe` 16
      sort (nub heights) `shouldBe` [0, t, 2 * t, 3 * t]
      -- Face 3 is the bottom-left quadrant of the pattern and is on the table;
      -- face 2, the top-left, is on top. Corners are written face by face in
      -- file order, four to a face.
      take 4 (drop 12 heights) `shouldBe` replicate 4 0
      take 4 (drop 8 heights) `shouldBe` replicate 4 (3 * t)

    it "states the bounds a POSITION accessor must carry, and states them truly" $ do
      glb <- folded "test/fixtures/quarter-fold.fold" >>= export DefaultThickness >>= parseGlb
      -- Compared as float32, which is what both are: the data is packed in
      -- single precision, and the bounds are written with the digits that
      -- single precision can hold. Widened to Double the two would disagree
      -- in the tenth decimal, about a number neither of them contains.
      let ps = vec3s glb 0
          accessor = nth 0 (at "accessors" (glbJson glb))
          stated k = map (realToFrac . asDouble) (items (at k accessor)) :: [Float]
          xs = [x | (x, _, _) <- ps]
          ys = [y | (_, y, _) <- ps]
          zs = [z | (_, _, z) <- ps]
      stated "min" `shouldBe` [minimum xs, minimum ys, minimum zs]
      stated "max" `shouldBe` [maximum xs, maximum ys, maximum zs]

    it "writes every face twice, wound both ways, in two materials" $ do
      glb <- folded "test/fixtures/quarter-fold.fold" >>= export DefaultThickness >>= parseGlb
      let json = glbJson glb
          primitives = at "primitives" (nth 0 (at "meshes" json))
          prims = items primitives
          front = triangles glb (asInt (at "indices" (nth 0 primitives)))
          back = triangles glb (asInt (at "indices" (nth 1 primitives)))
      length prims `shouldBe` 2
      -- Four quads, two triangles each.
      length front `shouldBe` 8
      -- The back copy is the front copy with each triangle turned over: the
      -- same corners, the two after the first swapped. That is what puts its
      -- front on the other side, and what lets one material show from each.
      back `shouldBe` [(a, c, b) | (a, b, c) <- front]
      map (at "name") (items (at "materials" json)) `shouldBe` [String "paper", String "paper underside"]
      map (asInt . at "material") prims `shouldBe` [0, 1]

    it "turns FOLD's z-up into glTF's y-up without mirroring" $
      -- A quarter turn about x, not a swap of two axes: the swap is a
      -- reflection, and the model would come out as its own mirror image.
      toGltfAxes (V3 1 2 3) `shouldBe` V3 1 3 (-2)

    it "names the model after the frame" $ do
      glb <- folded "test/fixtures/quarter-fold.fold" >>= export DefaultThickness >>= parseGlb
      at "name" (nth 0 (at "nodes" (glbJson glb))) `shouldBe` String "Quarter folds"

    it "writes a crease pattern as one flat sheet" $ do
      -- Nothing overlaps, so nothing is lifted: every corner at height zero,
      -- and each of the two faces still owns its own three.
      glb <- export DefaultThickness flatSheet >>= parseGlb
      let ps = vec3s glb 0
      length ps `shouldBe` 6
      [y | (_, y, _) <- ps] `shouldBe` replicate 6 0

    it "writes a form with paper in the air exactly as folded" $ do
      -- Its layers are not separated -- that is the general case this does not
      -- do yet -- so the heights are the file's own z values, turned into y.
      glb <- fixture "test/fixtures/simple.fold" >>= export DefaultThickness >>= parseGlb
      sort (nub [y | (_, y, _) <- vec3s glb 0]) `shouldBe` [-1, 0, 1]

  describe "the thickness" $ do
    it "is what separates a twist from a refusal" $ do
      -- A twist's layers run in a circle and have no numbers, so with any
      -- thickness at all there is nothing to lift each face by, and the export
      -- says so. At zero no layer order is asked for and the paper is written
      -- as folded, which is the one way to get a twist out.
      fr <- folded "test/fixtures/thirds-pinwheel.fold"
      case renderGlb defaultBudget DefaultThickness fr of
        Left err@(GltfRefused (ImpossibleStacking _)) ->
          -- Said in terms of height, not of painting, and with the way out.
          renderGltfError err `shouldSatisfy` T.isInfixOf "thickness of zero"
        other -> expectationFailure ("expected the twist to be refused, got " <> either show (const "a model") other)
      _ <- export (Thickness 0) fr
      pure ()

    it "is used as given" $ do
      fr <- folded "test/fixtures/quarter-fold.fold"
      glb <- export (Thickness 0.25) fr >>= parseGlb
      sort (nub [y | (_, y, _) <- vec3s glb 0]) `shouldBe` [0, 0.25, 0.5, 0.75]

    it "refuses a thickness that is not a distance" $ do
      fr <- folded "test/fixtures/quarter-fold.fold"
      renderGlb defaultBudget (Thickness (-1)) fr `shouldBe` Left (GltfBadThickness (-1))
      case renderGlb defaultBudget (Thickness (0 / 0)) fr of
        Left (GltfBadThickness _) -> pure ()
        _ -> expectationFailure "NaN was accepted as a thickness"

  describe "what is refused" $ do
    it "refuses a face the fan would triangulate wrongly" $
      -- A concave quad, planar and tilted out of the sheet so that no layer
      -- solver sees it first. A fan from its first corner would cover paper
      -- that is not there.
      renderGlb defaultBudget DefaultThickness concaveInTheAir
        `shouldBe` Left (GltfConcaveFace (FaceId 0))

    it "refuses a frame with no faces, which has no surface to write" $ do
      fr <- fixture "test/fixtures/unit-square.fold"
      renderGlb defaultBudget DefaultThickness fr `shouldBe` Left GltfNoFaces

  describe "the pieces" $ do
    it "rounds a coordinate to six decimals and forgets the sign of zero" $
      -- The binary sibling of formatNumber: folding noise like 6e-17 becomes
      -- 0, and -0.0 becomes 0.0, so that the same fold gives the same bytes.
      packable (V3 (-0.0) 6e-17 0.12345678) `shouldBe` (0, 0, 0.123457)

    it "converts a colour from sRGB to the linear light glTF wants" $ do
      linearOf (Colour "#ffffff") `shouldBe` (1, 1, 1)
      linearOf (Colour "#000000") `shouldBe` (0, 0, 0)
      -- Mid grey by the digits is a fifth by the light: the whole point of
      -- converting, and the reason paper written unconverted comes out washed
      -- out.
      let (r, _, _) = linearOf (Colour "#808080")
      abs (r - 0.2159) `shouldSatisfy` (< 1e-3)

  describe "golden files" $ do
    -- Read every diff before accepting one. A .glb is opaque in a text diff,
    -- so the failure message gives the offset of the first byte that differs:
    -- inside the JSON chunk is a change of document, inside the binary chunk
    -- is a change of geometry.
    it "writes the quarter fold exactly as recorded" $
      folded "test/fixtures/quarter-fold.fold"
        >>= export DefaultThickness
        >>= goldenBytes "test/golden/quarter-fold-folded.glb"

    it "writes the crane exactly as recorded" $
      folded "test/fixtures/crane.fold"
        >>= export DefaultThickness
        >>= goldenBytes "test/golden/crane-folded.glb"

    it "writes a form with paper in the air exactly as recorded" $
      fixture "test/fixtures/simple.fold"
        >>= export DefaultThickness
        >>= goldenBytes "test/golden/simple.glb"
