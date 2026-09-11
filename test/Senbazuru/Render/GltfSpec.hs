-- |
-- Tests for the 3D export.
--
-- Three layers, tested separately. The container — magic, lengths, alignment —
-- is what a viewer checks before it reads a byte of geometry, so it gets exact
-- assertions. The geometry is read back out of our own output and compared
-- with the frame it came from, which is the one test that would catch an axis
-- swapped the wrong way or a shared crease split into different positions. And the whole
-- file gets a golden, because "these exact bytes" is the contract a viewer
-- holds us to.
--
-- The reader in this file is deliberately naive: it walks the JSON with aeson
-- and pulls floats out of the binary chunk by hand. A real glTF loader would
-- be a dependency the test suite does not need, and would also hide the very
-- offsets and alignments these tests exist to pin.
module Senbazuru.Render.GltfSpec (spec) where

import BasicBases (baseFrame, frogMilestones)
import Control.Applicative ((<|>))
import Control.Monad (forM_)
import Data.Aeson (Value (..), decodeStrict, toJSON)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Foldable (toList)
import Data.List (nub, sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Word (Word32, Word8)
import GHC.Float (castFloatToWord32, castWord32ToFloat)
import Senbazuru.Diagram (Colour (..))
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FaceOrder (..),
    FoldFile (..),
    Frame (..),
    Stacking (..),
    VertexId (..),
    emptyFrame,
  )
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (foldFrame, foldFrameWith)
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Surface qualified as Paper
import Senbazuru.Render.Gltf
import Test.Golden (goldenBytes)
import Test.Hspec

-- | A fixture's key frame, with the name the command line would give it: the
-- frame's title, else the file's. The crane's title lives on the file.
fixture :: FilePath -> IO (Maybe Text, Frame)
fixture path = do
  bytes <- BS.readFile path
  f <- either (fail . ("decode failed: " <>)) pure (decodeFoldFile bytes)
  let fr = keyFrame f
  pure (frameTitle fr <|> fileTitle f, fr)

-- | A fixture folded along its own angles.
folded :: FilePath -> IO (Maybe Text, Frame)
folded path = do
  (name, fr) <- fixture path
  either (fail . ("fold failed: " <>) . show) (pure . (,) name) (foldFrame fr)

-- | Export, or fail the test saying why.
export :: ExportMode -> (Maybe Text, Frame) -> IO ByteString
export t (name, fr) = either (fail . ("export failed: " <>) . show) pure (renderGlb defaultBudget t name fr)

-- | Export a frame that has no file to take a name from.
exportFrame :: ExportMode -> Frame -> Either GltfError ByteString
exportFrame t = renderGlb defaultBudget t Nothing

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
      bytes <- folded "test/fixtures/quarter-fold.fold" >>= export CompletePaper
      glb <- parseGlb bytes
      -- The header's declared length is the file's, and both chunks are
      -- padded to the four-byte boundary the specification requires -- the
      -- JSON one with spaces, which a parser skips, and the binary one with
      -- zeros, which nothing reads.
      glbTotal glb `shouldBe` BS.length bytes
      glbJsonLength glb `mod` 4 `shouldBe` 0
      glbBinLength glb `mod` 4 `shouldBe` 0
      glbTotal glb `shouldBe` 12 + 8 + glbJsonLength glb + 8 + glbBinLength glb

    it "gives the same bytes for the same model with different noise in it" $ do
      -- Folding leaves noise in the last bits of coordinates that are really
      -- zero, and float32 keeps -0.0 distinct from 0.0, so the same fold could
      -- differ in a byte between two runs. Rounding before packing is what
      -- makes them agree. Asserted against a copy of the frame with the noise
      -- put in by hand -- exporting one frame twice proves only that the
      -- function is a function.
      (name, fr) <- folded "test/fixtures/quarter-fold.fold"
      let noisy = fr {verticesCoords = map (zipWith (+) [6e-17, -0.0, 3e-17]) (verticesCoords fr)}
      a <- export CompletePaper (name, fr)
      b <- export CompletePaper (name, noisy)
      b `shouldBe` a

  describe "the geometry" $ do
    it "keeps all four quarter-fold layers at their shared material positions" $ do
      named <- folded "test/fixtures/quarter-fold.fold"
      glb <- export CompletePaper named >>= parseGlb
      length (vec3s glb 0) `shouldBe` 16
      nub [y | (_, y, _) <- vec3s glb 0] `shouldBe` [0]

    it "states the bounds a POSITION accessor must carry, and states them truly" $ do
      glb <- folded "test/fixtures/quarter-fold.fold" >>= export CompletePaper >>= parseGlb
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
      glb <- folded "test/fixtures/quarter-fold.fold" >>= export CompletePaper >>= parseGlb
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

    it "names the model as it was asked to" $ do
      glb <- folded "test/fixtures/quarter-fold.fold" >>= export CompletePaper >>= parseGlb
      at "name" (nth 0 (at "nodes" (glbJson glb))) `shouldBe` String "Quarter folds"
      -- The crane's title is on the file, not the frame, which is where most
      -- files keep it; the caller passes whichever it has, as render does.
      glb' <- folded "test/fixtures/crane.fold" >>= export CompletePaper >>= parseGlb
      at "name" (nth 0 (at "nodes" (glbJson glb'))) `shouldBe` String "Crane"
      glb'' <- either (fail . show) parseGlb (exportFrame CompletePaper flatSheet)
      at "name" (nth 0 (at "nodes" (glbJson glb''))) `shouldBe` Null

    it "writes a crease pattern as one flat sheet" $ do
      -- Nothing overlaps, so nothing is lifted: every corner at height zero,
      -- and each of the two faces still owns its own three.
      glb <- either (fail . show) parseGlb (exportFrame CompletePaper flatSheet)
      let ps = vec3s glb 0
      length ps `shouldBe` 6
      [y | (_, y, _) <- ps] `shouldBe` replicate 6 0

    it "never asks the layer solver about a crease pattern" $ do
      -- One face wound backwards, which real files do and render draws without
      -- comment. The solver would refuse it -- the two faces' windings disagree
      -- about which side is up across their shared crease -- and a crease
      -- pattern has no layers for it to order anyway. A flag deciding which
      -- files are acceptable is the failure this guards against.
      let backwards = flatSheet {facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 3, 2]]}
      glb <- either (fail . show) parseGlb (exportFrame CompletePaper backwards)
      length (vec3s glb 0) `shouldBe` 6

    it "writes a form with paper in the air exactly as folded" $ do
      -- The heights are the file's own z values, turned into y.
      glb <- fixture "test/fixtures/simple.fold" >>= export CompletePaper >>= parseGlb
      sort (nub [y | (_, y, _) <- vec3s glb 0]) `shouldBe` [-1, 0, 1]

    it "checks a file's own faceOrders on every path, whether or not it uses them" $ do
      -- render refuses an order naming a face that is not there. The paths that
      -- never consult the orders -- paper in the air, and complete-paper mode
      -- used to skip the check and export the file without a word.
      (_, simple) <- fixture "test/fixtures/simple.fold"
      let bad = simple {faceOrders = faceOrders simple <> [FaceOrder (FaceId 99) (FaceId 0) Above]}
      exportFrame CompletePaper bad `shouldBe` Left (GltfRefused (FaceOrderOutOfRange (FaceId 99) 4))
      (_, quarter) <- folded "test/fixtures/quarter-fold.fold"
      exportFrame CompletePaper quarter {faceOrders = [FaceOrder (FaceId 99) (FaceId 0) Above]}
        `shouldBe` Left (GltfRefused (FaceOrderOutOfRange (FaceId 99) 4))

    it "writes more vertices than sixteen bits can index, with wider indices" $ do
      -- A grid of 128 by 128 quads: 65,536 corners once every face owns its
      -- own, one more than a 16-bit index reaches.
      let n = 128 :: Int
          at' i j = i * (n + 1) + j
          grid =
            emptyFrame
              { verticesCoords = [[fromIntegral i, fromIntegral j] | i <- [0 .. n], j <- [0 .. n]],
                edgesVertices = [],
                facesVertices =
                  [ map VertexId [at' i j, at' (i + 1) j, at' (i + 1) (j + 1), at' i (j + 1)]
                    | i <- [0 .. n - 1],
                      j <- [0 .. n - 1]
                  ]
              }
      glb <- either (fail . show) parseGlb (exportFrame CompletePaper grid)
      asInt (at "count" (nth 0 (at "accessors" (glbJson glb)))) `shouldBe` 65536
      -- 5125 is UNSIGNED_INT; 5123, the usual, is UNSIGNED_SHORT.
      asInt (at "componentType" (nth 1 (at "accessors" (glbJson glb)))) `shouldBe` 5125

  describe "material geometry and visible scenes" $ do
    it "stores physical thickness without displacing material vertices" $ do
      (name, source) <- fixture "test/fixtures/quarter-fold.fold"
      result <- either (fail . show) pure (foldFrameWith source)
      sheet <- either (fail . show) pure (Paper.surfaceFromFolded result >>= Paper.withPhysicalThickness (Just 0.25))
      bytes <- either (fail . show) pure (renderSurfaceGlb defaultBudget CompletePaper name sheet)
      glb <- parseGlb bytes
      -- Physical thickness is metadata, not an instruction to open crease gaps.
      nub [y | (_, y, _) <- vec3s glb 0] `shouldBe` [0]
      -- Graphics still duplicate corners for their per-face layout. Material
      -- identities belong to the nine-vertex surface, not those copies.
      length (Paper.surfaceSamples sheet) `shouldBe` 9
      length (vec3s glb 0) `shouldBe` 16
      asDouble (at "physicalThickness" (at "senbazuru" (at "extras" (glbJson glb)))) `shouldBe` 0.25
      checkMaterialReferences glb

    it "preserves intentional cuts even where their graphics corners coincide" $ do
      let cut = emptyFrame {verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]], facesVertices = map (map VertexId) [[0, 1, 2], [3, 4, 5]]}
      glb <- either (fail . show) parseGlb (exportFrame VisiblePaper cut)
      checkMaterialReferences glb
      let stored = at "frame" (at "senbazuru" (at "extras" (glbJson glb)))
      map (map asInt . items) (items (at "faces_vertices" stored)) `shouldBe` [[0, 1, 2], [3, 4, 5]]

    it "retains supplied material maps and layer constraints, but drops stale frame extras" $ do
      (_, source) <- fixture "test/fixtures/quarter-fold.fold"
      result <- either (fail . show) pure (foldFrameWith source)
      known <- either (fail . show) pure (Paper.surfaceFromFolded result)
      let supplied = (Paper.materialFrame known) {faceOrders = [FaceOrder (FaceId 0) (FaceId 1) Above]}
          stale = supplied {frameExtras = KM.insert "old-contact-check" (Bool True) (frameExtras supplied)}
      sheet <- either (fail . show) pure (Paper.surfaceFromFrame stale >>= Paper.withLayerRequirements (V3 0 0 1) [(FaceId 0, FaceId 1)])
      glb <- either (fail . show) parseGlb (renderSurfaceGlb defaultBudget CompletePaper Nothing sheet)
      let metadata = at "senbazuru" (at "extras" (glbJson glb))
          stored = at "frame" metadata
      at "faceOrders" stored `shouldBe` toJSON (faceOrders supplied)
      at "senbazuru:material_coords" stored `shouldBe` at "senbazuru:material_coords" (toJSON supplied)
      at "old-contact-check" stored `shouldBe` Null
      at "direction" (at "layerRequirements" metadata) `shouldBe` toJSON ([0, 0, 1] :: [Int])
      at "lowerUpper" (at "layerRequirements" metadata) `shouldBe` toJSON ([[0, 1]] :: [[Int]])

    it "provides a stable scene and a complete inspection scene for a quarter fold" $ do
      named <- folded "test/fixtures/quarter-fold.fold"
      glb <- export VisiblePaper named >>= parseGlb
      let json = glbJson glb
      map (at "name") (items (at "scenes" json)) `shouldBe` [String "Visible paper", String "Complete paper"]
      -- Two exposed quads, one on each side. No buried duplicate triangles
      -- remain in the default scene; every layer survives in the other one.
      let primitives = items (at "primitives" (nth 0 (at "meshes" json)))
      sum [length (triangles glb (asInt (at "indices" p))) | p <- primitives] `shouldBe` 4
      forM_ (items (at "meshes" json)) $ \mesh -> do
        let ps = items (at "primitives" mesh)
        forM_ ps $ \primitive ->
          nub [y | (_, y, _) <- vec3s glb (asInt (at "POSITION" (at "attributes" primitive)))] `shouldBe` [0]

    it "exports a cyclic pinwheel without inventing layer heights" $ do
      named <- folded "test/fixtures/thirds-pinwheel.fold"
      glb <- export VisiblePaper named >>= parseGlb
      length (items (at "scenes" (glbJson glb))) `shouldBe` 2

    it "keeps tiny quarter folds unseparated" $ do
      (name, fr) <- folded "test/fixtures/quarter-fold.fold"
      let tiny = fr {verticesCoords = map (map (* 0.001)) (verticesCoords fr)}
      glb <- export VisiblePaper (name, tiny) >>= parseGlb
      nub [y | (_, y, _) <- vec3s glb 0] `shouldBe` [0]

  describe "material identities across every basic base" $
    forM_ ["book", "quarter-fold", "square", "waterbomb", "fish", "bird", "helmet", "organ", "frog", "boat", "pig", "diamond"] $ \name ->
      it (name ++ " keeps every graphics corner attached to its material") $ do
        let path = if name == "quarter-fold" then "examples/quarter-fold.fold" else "examples/" ++ name ++ "-base.fold"
        named <- folded path
        glb <- export VisiblePaper named >>= parseGlb
        checkMaterialReferences glb

  describe "moving and ambiguous paper" $ do
    it "exports every checked bird state through both scenes" $ do
      bytes <- BS.readFile "examples/bird-base-sequence.fold"
      file <- either fail pure (decodeFoldFile bytes)
      length (otherFrames file) `shouldBe` 16
      forM_ (otherFrames file) $ \fr -> do
        glb <- either (fail . show) parseGlb (exportFrame VisiblePaper fr)
        checkMaterialReferences glb

    it "exports all five frog guide milestones through both scenes" $ do
      length frogMilestones `shouldBe` 5
      forM_ frogMilestones $ \(_, base) -> do
        source <- either (fail . show) pure (baseFrame base)
        fr <- either (fail . show) pure (foldFrame source)
        glb <- either (fail . show) parseGlb (exportFrame VisiblePaper fr)
        checkMaterialReferences glb

    it "refuses unresolved coplanar contact in an open model but keeps the inspection export" $ do
      -- Two touching squares and one upright triangle. No relation tells us
      -- which square is exposed; actual depth cannot decide a tie.
      let ambiguous = emptyFrame {frameClasses = ["foldedForm"], verticesCoords = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [0, 0, 1]], facesVertices = map (map VertexId) [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 8]]}
      exportFrame VisiblePaper ambiguous `shouldSatisfy` isLeft
      _ <- either (fail . show) parseGlb (exportFrame CompletePaper ambiguous)
      ordered <- either (fail . show) parseGlb (exportFrame VisiblePaper ambiguous {faceOrders = [FaceOrder (FaceId 0) (FaceId 1) Above]})
      checkMaterialReferences ordered

    it "refuses contradictory order over a common patch instead of exporting a hole" $ do
      let wrong = emptyFrame {frameClasses = ["foldedForm"], verticesCoords = [[0, 0], [1, 0], [0, 1]], facesVertices = replicate 3 (map VertexId [0, 1, 2]), faceOrders = [FaceOrder (FaceId a) (FaceId b) Above | (a, b) <- [(0, 1), (1, 2), (2, 0)]]}
      exportFrame VisiblePaper wrong `shouldSatisfy` isLeft

  describe "what is refused" $ do
    it "refuses a face the fan would triangulate wrongly" $
      -- A concave quad, planar and tilted out of the sheet so that no layer
      -- solver sees it first. A fan from its first corner would cover paper
      -- that is not there.
      exportFrame CompletePaper concaveInTheAir
        `shouldBe` Left (GltfConcaveFace (FaceId 0))

    it "refuses a face too thin to have a plane, not only one with none at all" $
      -- Three corners a rounding error off a line: a normal that is not
      -- exactly zero, and a face that fans into triangles of no area. Judged
      -- by area, like everything else that asks whether a polygon is one.
      exportFrame
        CompletePaper
        emptyFrame
          { frameClasses = ["foldedForm"],
            verticesCoords = [[0, 0, 0], [1, 0, 0.5], [2, 0, 1 + 1e-12]],
            facesVertices = [map VertexId [0, 1, 2]]
          }
        `shouldBe` Left (GltfRefused (FaceWithoutNormal (FaceId 0)))

    it "refuses a coordinate single precision cannot hold" $ do
      -- Written through, 1e40 would arrive as the bare token Infinity in the
      -- JSON bounds, which no parser accepts, with the export reporting
      -- success. Not a number is refused for the same reason, with its own
      -- message rather than one about a face's normal.
      let huge = flatSheet {verticesCoords = [[1e40, 0], [1, 0], [1, 1], [0, 1]]}
      exportFrame CompletePaper huge `shouldBe` Left (GltfUnwritableCoordinate 1e40)
      case exportFrame CompletePaper flatSheet {verticesCoords = [[0 / 0, 0], [1, 0], [1, 1], [0, 1]]} of
        Left (GltfUnwritableCoordinate _) -> pure ()
        other -> expectationFailure ("NaN was not refused as a coordinate: " <> either show (const "exported") other)

    it "traces the faces of a crease pattern that records none, and writes them" $ do
      -- The same tracing foldFrame does, here for the reason --layer-budget
      -- had to reach both backends: a policy that reaches one of them is a
      -- policy that is wrong on the other.
      let square =
            flatSheet
              { facesVertices = [],
                edgesVertices =
                  [ (VertexId 0, VertexId 1),
                    (VertexId 1, VertexId 2),
                    (VertexId 2, VertexId 3),
                    (VertexId 3, VertexId 0),
                    (VertexId 0, VertexId 2)
                  ],
                edgesAssignment = [Border, Border, Border, Border, Valley],
                edgesFoldAngle = []
              }
      -- Compared against the same sheet with those two faces written out by
      -- hand, byte for byte. "It exported something" would be true of every
      -- possible success, including tracing one face, or the wrong two.
      -- The second ring is written from corner 2 rather than corner 0, which
      -- is where the walk happened to start, and the export writes corners in
      -- the order it is given them. So this pins the rotation too: a change to
      -- where a trace begins changes the bytes, and should have to say so.
      let stated =
            square
              { facesVertices =
                  [ [VertexId 0, VertexId 1, VertexId 2],
                    [VertexId 2, VertexId 3, VertexId 0]
                  ]
              }
      exportFrame CompletePaper square `shouldBe` exportFrame CompletePaper stated

    it "cuts creases that cross, rather than refusing the frame they are in" $ do
      -- unit-square.fold has been refused here twice over: for recording no
      -- faces, then for its creases crossing. Both were about what the file
      -- left out rather than about the paper, and both are now worked out.
      (_, fr) <- fixture "test/fixtures/unit-square.fold"
      -- Compared against the same pattern cut by hand: the three creases
      -- through the middle of the sheet become six through one new vertex at
      -- (0.5, 0.5), and the six faces that cuts the square into come out in
      -- that order. "It exported something" would be true of every possible
      -- success, including cutting it into three vertices a hair apart.
      let byHand =
            fr
              { verticesCoords = verticesCoords fr <> [[0.5, 0.5]],
                edgesVertices =
                  [ (VertexId a, VertexId b)
                    | (a, b) <-
                        [ (0, 4),
                          (4, 1),
                          (1, 5),
                          (5, 2),
                          (2, 6),
                          (6, 3),
                          (3, 7),
                          (7, 0),
                          (4, 8),
                          (8, 6),
                          (7, 8),
                          (8, 5),
                          (0, 8),
                          (8, 2)
                        ]
                  ],
                edgesAssignment =
                  replicate 8 Border <> [Valley, Valley, Mountain, Mountain, Flat, Flat],
                edgesFoldAngle =
                  replicate 8 0 <> [180, 180, -180, -180, 0, 0]
              }
      exportFrame CompletePaper fr `shouldBe` exportFrame CompletePaper byHand

    it "refuses a frame with no creases at all, which has no surface to write" $ do
      let bare = flatSheet {facesVertices = [], edgesVertices = [], edgesAssignment = []}
      exportFrame CompletePaper bare `shouldBe` Left GltfNoFaces

  describe "the pieces" $ do
    it "rounds a coordinate to the quantum and forgets the sign of zero" $ do
      -- The binary sibling of formatNumber: folding noise like 6e-17 becomes
      -- 0, and -0.0 becomes 0.0, so that the same fold gives the same bytes.
      -- The sign has to be checked through the bits, because (-0.0) == 0 is
      -- True and an assertion on the value cannot see it -- the very gotcha
      -- this exists for.
      let (x, y, z) = packable 1e-6 (V3 (-0.0) 6e-17 0.12345678)
      castFloatToWord32 x `shouldBe` 0
      castFloatToWord32 y `shouldBe` 0
      z `shouldBe` 0.123457
      -- A value just under half a quantum below zero rounds to zero, not to
      -- negative zero.
      castFloatToWord32 (let (v, _, _) = packable 1e-6 (V3 (-4e-7) 0 0) in v) `shouldBe` 0

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
        >>= export VisiblePaper
        >>= goldenBytes "test/golden/quarter-fold-folded.glb"

    it "writes the crane exactly as recorded" $
      folded "test/fixtures/crane.fold"
        >>= export VisiblePaper
        >>= goldenBytes "test/golden/crane-folded.glb"

    it "writes a form with paper in the air exactly as recorded" $
      fixture "test/fixtures/simple.fold"
        >>= export VisiblePaper
        >>= goldenBytes "test/golden/simple.glb"

-- Reconstruct every graphics vertex from its source material ids. Clipping
-- introduces weighted corners; complete-paper copies must keep a single id.
checkMaterialReferences :: Glb -> Expectation
checkMaterialReferences glb = do
  let json = glbJson glb
      originals = at "vertices_coords" (at "frame" (at "senbazuru" (at "extras" json)))
      original = items originals
      sourceFaces = items (at "faces_vertices" (at "frame" (at "senbazuru" (at "extras" json))))
      point i = case map asDouble (items (nth i originals)) of
        [x, y, z] -> (x, z, -y)
        _ -> (0, 0, 0)
  forM_ (items (at "meshes" json)) $ \mesh -> do
    let primitives = items (at "primitives" mesh)
        weights = items (at "materialWeights" (at "extras" mesh))
    forM_ primitives $ \primitive -> do
      let ps = vec3s glb (asInt (at "POSITION" (at "attributes" primitive)))
      length ps `shouldBe` length weights
      forM_ (zip ps weights) $ \((x, y, z), anchors) -> do
        let refs = [(asInt (nth 0 pair), asDouble (nth 1 pair)) | pair <- items anchors]
        refs `shouldSatisfy` (not . null)
        forM_ refs $ \(vid, weight) -> do
          vid `shouldSatisfy` (>= 0)
          vid `shouldSatisfy` (< length original)
          weight `shouldSatisfy` (>= (-1e-8))
        abs (sum (map snd refs) - 1) `shouldSatisfy` (< 1e-8)
        let expected component = sum [weight * component (point vid) | (vid, weight) <- refs]
        abs (realToFrac x - expected (\(a, _, _) -> a)) `shouldSatisfy` (< 3e-6)
        abs (realToFrac y - expected (\(_, b, _) -> b)) `shouldSatisfy` (< 3e-6)
        abs (realToFrac z - expected (\(_, _, c) -> c)) `shouldSatisfy` (< 3e-6)

      let indices = triangles glb (asInt (at "indices" primitive))
          panels = map asInt (items (at "materialFaces" (at "extras" primitive)))
          graphics = zip [0 ..] [V3 (realToFrac x) (realToFrac y) (realToFrac z) | (x, y, z) <- ps]
          sourcePoint vid = let (x, y, z) = point vid in V3 x y z
      length panels `shouldBe` length indices
      forM_ (zip panels indices) $ \(fid, (a, b, c)) -> do
        fid `shouldSatisfy` (>= 0)
        fid `shouldSatisfy` (< length sourceFaces)
        let ids = case drop fid sourceFaces of
              face : _ -> map asInt (items face)
              [] -> []
        forM_ [a, b, c] $ \i -> do
          i `shouldSatisfy` (>= 0)
          i `shouldSatisfy` (< length ps)
          let anchors = case drop i weights of
                value : _ -> items value
                [] -> []
          map (asInt . nth 0) anchors `shouldSatisfy` all (`elem` ids)
        case (lookup a graphics, lookup b graphics, lookup c graphics) of
          (Just pa, Just pb, Just pc) -> do
            let actualNormal = cross (pb ^-^ pa) (pc ^-^ pa)
                sourceNormal = polygonNormal (map sourcePoint ids)
                side = if asInt (at "material" primitive) == 0 then 1 else -1
            side * dot actualNormal sourceNormal `shouldSatisfy` (> 0)
          _ -> expectationFailure "triangle names a missing graphics corner"
      -- A graphics copy with one material id must pack to exactly that id's
      -- position. Sharing lighting vertices must never open a crease gap.
      forM_ (zip ps weights) $ \(actual, anchors) ->
        case items anchors of
          [pair] | asDouble (nth 1 pair) == 1 -> do
            let (x, y, z) = point (asInt (nth 0 pair))
            actual `shouldBe` (realToFrac x, realToFrac y, realToFrac z)
          _ -> pure ()
