-- |
-- Module      : Senbazuru.Render.Gltf
-- Description : Writing a folded form out as a 3D model, in glTF's binary form.
--
-- A folded form is a three-dimensional object, and by the time senbazuru has
-- drawn one it already holds everything a 3D viewer wants: where every face
-- is, which way it faces, and which layer is over which. This module writes
-- that out as a @.glb@ — glTF 2.0 in its self-contained binary container —
-- which opens in Blender, in three.js, in the Windows and macOS viewers, and in
-- most things that can show a mesh at all. It is the first output someone can
-- turn over in their hands, and the fastest way to see that a fold went wrong.
--
-- == Two scenes, one geometry
--
-- The default scene draws only exposed paper on each side of each plane.
-- Removing buried coplanar regions resolves depth ties without moving any
-- panel or opening gaps at its creases. A second scene retains every layer.
-- 'CompletePaper' exports that inspection scene alone; a generic viewer may
-- show depth flicker there because it cannot interpret origami layer orders.
--
-- "Senbazuru.Render.PaperMesh" derives the visible pieces. Its clipped corners
-- retain weighted references to original material vertices. Both scenes store
-- those references and original panel ids in glTF extras, alongside the source
-- frame and its layer requirements. Graphics copies never become material ids.
-- Optional physical thickness remains a property; it does not move vertices.
--
-- == Two sides, up to two primitives
--
-- Origami paper is coloured on one side and white on the other, and the export
-- says so. glTF has no notion of a material with two colours, but it culls
-- triangles seen from behind by default, and a triangle's front is decided by
-- the order its corners are listed in. In the complete scene each face is
-- written twice: once wound as the file has it, in the paper's colour, and once
-- wound the other
-- way, in the underside's. Each copy shows from one side only, and together
-- they are a sheet with a front and a back. The two share one set of positions
-- and differ only in their index lists. The visible scene omits buried sides;
-- an unused colour has no primitive.
--
-- The winding is the file's, as "Senbazuru.Origami.Layers" takes it, because a
-- face's front /is/ its winding in FOLD. Frames from
-- "Senbazuru.Origami.Folding" are wound counterclockwise on purpose, so their
-- fronts are the side a crease pattern is drawn on.
--
-- No normals are written. The specification requires a viewer to compute flat
-- normals when a mesh carries none, and flat is exactly right for paper.
--
-- No crease lines are written either, and no animation: the per-face rigid
-- transforms an animation would need come back from
-- 'Senbazuru.Origami.Folding.foldFrameWith', but the intermediate angles that
-- close their loops require a suitable sequence (#56).
--
-- Because the front /is/ the file's winding, a file whose faces are all wound
-- backwards comes out here with its two colours swapped, exactly as it does on
-- the page, and for the same reason: nothing in such a file says which side is
-- which.
--
-- == Why this does not go through 'Senbazuru.Diagram'
--
-- Every other backend consumes a 'Senbazuru.Diagram.Diagram', and the
-- architecture says new ones should. A 'Diagram' is two-dimensional — it has
-- 'Senbazuru.Geometry.V2' and no depth — so a 3D exporter is the first thing
-- that genuinely cannot. It consumes "Senbazuru.Origami.Surface" and obtains
-- its validated panels through that representation. The FOLD entry point
-- traces absent faces once before constructing the surface. Geometry stays
-- shared until the display policy above assembles the graphics buffer.
--
-- == Things that read as mistakes and are not
--
-- * __The axis swap.__ FOLD folded forms treat @z@ as up. glTF treats @y@ as
--   up. A point @(x, y, z)@ is written as @(x, z, -y)@, which is a quarter turn
--   about @x@ — a rotation, so left and right stay where they were. Mapping
--   @(x, z, y)@ instead would be a reflection, and the model would come out as
--   its own mirror image, which folds perfectly well and is not the model in
--   the file.
--
-- * __Colours are converted before they are written.__ A hex colour like
--   @#faf8f3@ is sRGB — the encoded space of every colour on the web — and
--   glTF wants its @baseColorFactor@ in linear light. Writing the hex digits
--   through unconverted gives a paper visibly too light.
--
-- * __Coordinates are rounded before they are packed.__ Folding leaves noise
--   like @6.1e-17@ in coordinates that are really zero, and float32 keeps a
--   negative zero distinct from a positive one, so two runs of the same fold
--   could differ in a byte. Rounding every coordinate to a millionth of the
--   model's span — through an integer, which has no negative zero to keep —
--   is the binary sibling of 'Senbazuru.Render.Svg.formatNumber', and it is
--   what lets a @.glb@ be golden-tested. Relative to the model, not absolute:
--   a millionth of a unit is coarser than a model a thousandth of a unit
--   across and finer than single precision can hold on one a thousand across.
module Senbazuru.Render.Gltf
  ( -- * Export
    renderGlb,
    renderSurfaceGlb,
    ExportMode (..),

    -- * Errors
    GltfError (..),
    renderGltfError,

    -- * Pieces exposed for testing
    toGltfAxes,
    quantumFor,
    packable,
    linearOf,
  )
where

import Data.Aeson ((.=))
import Data.Aeson qualified as A
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.List (foldl')
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Numeric (showFFloat, showHex)
import Senbazuru.Diagram (Colour, colourComponents)
import Senbazuru.Diagram.Style (paper, paperUnderside)
import Senbazuru.Explain (Explain (..), tshow)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Query
  ( Face (..),
    FoldError (..),
    frameVertices,
  )
import Senbazuru.Fold.Types (FaceId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry.Polygon (isConvex)
import Senbazuru.Geometry.V3 (V3 (..), modelSpan, polygonNormal)
import Senbazuru.Geometry.VectorSpace (norm)
import Senbazuru.Origami.Stacking (Budget)
import Senbazuru.Origami.Surface (Surface, SurfaceError (..), surfaceFaces, surfaceFrame, surfaceFromFrame, surfaceLayerRequirements, surfaceThickness)
import Senbazuru.Render.Camera (basisFrom, project)
import Senbazuru.Render.PaperMesh (PaperMeshError, PaperPiece (..), PaperVertex (..), completePaper, visiblePaper)

-- | The default includes a stable visible scene and the complete sheet.
-- The inspection mode needs no visibility solution and writes all layers only.
-- Both preserve shared positions; neither applies display displacement.
data ExportMode = VisiblePaper | CompletePaper
  deriving stock (Eq, Show)

-- | Why a frame could not be written out.
data GltfError
  = -- | The frame itself is unsound, or its layers cannot be stacked. The
    -- error is the frame's own, so that everything a file can be wrong about
    -- reaches a caller as one type.
    GltfRefused !FoldError
  | GltfSurfaceError !SurfaceError
  | GltfPaperMeshError !PaperMeshError
  | -- | A face is not convex, and the fan this cuts each face into would
    -- cover paper that is not there. Ear clipping would handle it and is not
    -- built.
    GltfConcaveFace !FaceId
  | -- | Nothing to build: no faces, and no creases to trace any from either.
    GltfNoFaces
  | -- | A coordinate that single precision cannot hold: not a number, or
    -- beyond about 3.4e38. Written through, it would arrive as the bare token
    -- @Infinity@ in the JSON, which no parser accepts.
    GltfUnwritableCoordinate !Double
  deriving stock (Eq, Show)

instance Explain GltfError where
  explain = \case
    GltfRefused err -> explain err
    GltfSurfaceError err -> explain err
    GltfPaperMeshError err -> explain err
    GltfConcaveFace (FaceId f) ->
      "face "
        <> tshow f
        <> " is not convex, and a 3D model is built from triangles fanned out"
        <> " from each face's first corner, which is only right for convex faces"
    GltfNoFaces -> "there are no creases here, so there is no surface to write"
    GltfUnwritableCoordinate c ->
      "the coordinate " <> tshow c <> " cannot be written in single precision"

-- | 'explain' for a 'GltfError', under the name the test suite already uses.
renderGltfError :: GltfError -> Text
renderGltfError = explain

-- | Write a frame as a binary glTF document.
--
-- The budget is how hard the layer solver may look, for a flat-folded frame
-- that carries no @faceOrders@ of its own; see
-- 'Senbazuru.Origami.Stacking.layerOrderFor'. The name, if any, goes on the
-- scene's one node, which is what a viewer lists the model as. It is the
-- caller's to choose because the frame alone does not always have one: a
-- file's title often lives on the file and not the frame.
--
-- The frame's @faceOrders@ are checked on every path, whether or not they end
-- up used, because @render@ refuses a file whose orders name a face that is
-- not there and a flag should not decide which files are acceptable.
renderGlb :: Budget -> ExportMode -> Maybe Text -> Frame -> Either GltfError ByteString
renderGlb budget mode name fr0 = do
  -- The same tracing "Senbazuru.Origami.Folding" does, and here for the same
  -- reason it takes a --layer-budget: a policy that reaches only one backend
  -- is a policy that is wrong on the other. A crease pattern that records no
  -- faces still has them, and exporting a flat sheet is a thing to be able to
  -- do with one.
  fr <- refused (withPlanarFaces fr0)
  verts <- refused (frameVertices fr)
  mapM_ writable verts
  sheet <- first surfaceError (surfaceFromFrame fr)
  renderSurfaceGlb budget mode name sheet
  where
    refused = first GltfRefused

-- | Export the same material geometry used by the SVG path. The default
-- includes a derived visible scene and a complete inspection scene. All
-- exported corners retain their source material references, even when clipping
-- introduces a new corner inside a panel. Physical thickness is metadata only.
renderSurfaceGlb :: Budget -> ExportMode -> Maybe Text -> Surface material -> Either GltfError ByteString
renderSurfaceGlb budget mode name sheet = do
  let fr = surfaceFrame sheet
  verts <- first GltfRefused (frameVertices fr)
  faces <- first surfaceError (surfaceFaces sheet)
  if null faces then Left GltfNoFaces else Right ()
  mapM_ writable verts
  let span' = modelSpan verts
      quantum = quantumFor span'
      speck = 1e-9 * max 1 span' * max 1 span'
  mapM_ (convexOrRefuse speck) faces
  complete <- first GltfPaperMeshError (completePaper sheet)
  scenes <- case mode of
    CompletePaper -> Right [("Complete paper", complete)]
    VisiblePaper -> do
      shown <- first GltfPaperMeshError (visiblePaper budget sheet)
      Right [("Visible paper", map (canonicalPiece quantum) shown), ("Complete paper", complete)]
  let requirements = [A.object ["direction" .= [x, y, z], "lowerUpper" .= [[unFaceId a, unFaceId b] | (a, b) <- pairs]] | (V3 x y z, pairs) <- maybe [] pure (surfaceLayerRequirements sheet)]
      storedPoint p = let (x, y, z) = packable quantum p in map (realToFrac :: Float -> Double) [x, y, z]
      -- Packing changes positions. Keep only our original-sheet map, whose
      -- meaning is independent of the posed coordinates; discard unknown
      -- metadata, including study contact reports that rounding could stale.
      storedFrame = fr {verticesCoords = map storedPoint verts, frameExtras = KM.filterWithKey (\key _ -> key == "senbazuru:material_coords") (frameExtras fr)}
      metadata = A.object (["version" .= (1 :: Int), "frame" .= storedFrame] ++ ["physicalThickness" .= t | Just t <- [surfaceThickness sheet]] ++ ["layerRequirements" .= r | r <- requirements])
  pure (assemble name quantum metadata scenes)

surfaceError :: SurfaceError -> GltfError
surfaceError (SurfaceFrameError err) = GltfRefused err
surfaceError err = GltfSurfaceError err

writable :: V3 -> Either GltfError ()
writable (V3 x y z) = mapM_ component [x, y, z]
  where
    component c
      | isNaN c || isInfinite c || abs c > singleMax = Left (GltfUnwritableCoordinate c)
      | otherwise = Right ()
    singleMax = 3.4e38

-- | The size of the rounding step the coordinates go through: a millionth of
-- the model's span, and one unit's millionth for a model with no span at all,
-- which is a point and rounds to itself either way.
quantumFor :: Double -> Double
quantumFor span'
  | span' > 0 = 1e-6 * span'
  | otherwise = 1e-6

-- | Refuse a face the fan would triangulate wrongly.
--
-- Convexity is judged in the face's own plane: its corners are projected
-- through a basis whose forward axis is the face's normal, which is the one
-- direction in which a flat polygon has no extent. A face with no area to
-- speak of — collinear or repeated corners, within the speck — has no plane to
-- judge in and no paper to write, and is refused as the frame's own kind of
-- error. Judged by area rather than by an exactly zero normal, because a
-- sliver a rounding error wide passes every other test and fans into
-- triangles of no area.
convexOrRefuse :: Double -> Face -> Either GltfError ()
convexOrRefuse speck f
  -- polygonNormal's length is twice the area.
  | norm normal <= 2 * speck = Left (GltfRefused (FaceWithoutNormal (faceId f)))
  | otherwise = case basisFrom normal (leastAligned normal) of
      Nothing -> Left (GltfRefused (FaceWithoutNormal (faceId f)))
      Just basis
        | isConvex speck (map (project basis) (faceCorners f)) -> Right ()
        | otherwise -> Left (GltfConcaveFace (faceId f))
  where
    normal = polygonNormal (faceCorners f)

    -- An up hint that cannot be parallel to the normal: whichever world axis
    -- the normal has the least of.
    leastAligned (V3 x y z)
      | abs x <= abs y && abs x <= abs z = V3 1 0 0
      | abs y <= abs z = V3 0 1 0
      | otherwise = V3 0 0 1

-- | FOLD's @z@-up point as glTF's @y@-up point.
--
-- A quarter turn about @x@, so that up stays up and the model is not
-- mirrored. See the module header for why the @-y@ is not a typo.
toGltfAxes :: V3 -> V3
toGltfAxes (V3 x y z) = V3 x z (negate y)

-- | A coordinate as it will be packed: rounded to a whole number of quanta
-- and narrowed to the single precision glTF stores.
--
-- Rounded in double precision, through an 'Integer', and narrowed afterwards.
-- The integer is what removes negative zero: @-0.0@ and @-4e-7@ both round to
-- the integer @0@, and an integer has no sign to keep. Do not replace this
-- with a rounding in 'Float' and a guard — @realToFrac@ of a negative zero
-- keeps its sign under optimisation and drops it without, and the goldens
-- would come to depend on the build flags.
packable :: Double -> V3 -> (Float, Float, Float)
packable quantum (V3 x y z) = (tidy x, tidy y, tidy z)
  where
    tidy c = realToFrac (fromIntegral (round (c / quantum) :: Integer) * quantum :: Double)

-- | A colour's channels in linear light, from 0 to 1, as glTF wants them.
--
-- The standard sRGB transfer function, inverted. A colour that is not six hex
-- digits has no channels, and comes out as black rather than as a failure:
-- the two colours this is applied to are constants of "Senbazuru.Diagram.Style"
-- and a wrong one is a test failure, not a runtime one.
linearOf :: Colour -> (Double, Double, Double)
linearOf c = case colourComponents c of
  Nothing -> (0, 0, 0)
  Just (r, g, b) -> (linear r, linear g, linear b)
  where
    linear v
      | v <= 0.04045 = v / 12.92
      | otherwise = ((v + 0.055) / 1.055) ** 2.4

-- | Pack each scene independently, with the same coordinates and material
-- references. Extras use original FOLD ids; POSITION indices belong only to
-- this graphics buffer. Empty colour channels have no accessor or primitive,
-- because glTF forbids zero-count accessors.
assemble :: Maybe Text -> Double -> A.Value -> [(Text, [PaperPiece])] -> ByteString
assemble title quantum metadata scenes =
  BL.toStrict . B.toLazyByteString $
    B.string7 "glTF"
      <> B.word32LE 2
      <> B.word32LE (fromIntegral total)
      <> chunk "JSON" spaces jsonBytes
      <> chunk "BIN\0" zeros binBytes
  where
    channelPieces ps side = [(start, p) | (start, p) <- zip (scanl (+) 0 (map (length . pieceCorners) ps)) ps, side `elem` pieceSides p]
    channel ps side = [(piecePanel p, if side then (start, start + i, start + i + 1) else (start, start + i + 1, start + i)) | (start, p) <- channelPieces ps side, i <- [1 .. length (pieceCorners p) - 2]]
    channels ps = [(side, ts) | side <- [True, False], let ts = channel ps side, not (null ts)]
    starts = scanl (+) 0 [1 + length (channels ps) | (_, ps) <- scenes]
    built = [buildMesh start ps | (start, (_, ps)) <- zip starts scenes]
    sections = concatMap snd built
    offsets = scanl (+) 0 [padded (BS.length bytes) | (bytes, _, _) <- sections]
    binBytes = BS.concat [bytes <> BS.replicate (padded (BS.length bytes) - BS.length bytes) 0 | (bytes, _, _) <- sections]
    jsonBytes = BL.toStrict (B.toLazyByteString json)
    total = 12 + 8 + padded (BS.length jsonBytes) + 8 + padded (BS.length binBytes)
    chunk tag filler bytes = B.word32LE (fromIntegral (padded (BS.length bytes))) <> B.string7 tag <> B.byteString bytes <> filler (padded (BS.length bytes) - BS.length bytes)
    encoded = B.lazyByteString . A.encode
    json =
      object
        [ ("asset", object [("version", string "2.0"), ("generator", string "senbazuru")]),
          ("scene", int 0),
          ("scenes", array [object [("name", string name), ("nodes", array [int i])] | (i, (name, _)) <- zip [0 ..] scenes]),
          ("nodes", array [object (("mesh", int i) : [("name", string t) | Just t <- [title]]) | i <- [0 .. length scenes - 1]]),
          ("meshes", array (map fst built)),
          ("extras", object [("senbazuru", encoded metadata)]),
          ("materials", array [material "paper" paper, material "paper underside" paperUnderside]),
          ("accessors", array [object (("bufferView", int i) : fields) | (i, (_, _, fields)) <- zip [0 ..] sections]),
          ("bufferViews", array [object [("buffer", int 0), ("byteOffset", int offset), ("byteLength", int (BS.length bytes)), ("target", int target)] | (offset, (bytes, target, _)) <- zip offsets sections]),
          ("buffers", array [object [("byteLength", int (BS.length binBytes))]])
        ]
    buildMesh start ps =
      let vertices = concatMap pieceCorners ps
          positions = map (packable quantum . toGltfAxes . paperPosition) vertices
          count = length positions
          wide = count > 65535
          indexType = if wide then 5125 else 5123
          packIndex i = if wide then B.word32LE (fromIntegral i) else B.word16LE (fromIntegral i)
          bytes builder = BL.toStrict (B.toLazyByteString builder)
          (lo, hi) = bounds positions
          positionSection = (bytes (mconcat [B.floatLE x <> B.floatLE y <> B.floatLE z | (x, y, z) <- positions]), 34962, [("componentType", int 5126), ("count", int count), ("type", string "VEC3"), ("min", triple lo), ("max", triple hi)])
          indexSection (_, ts) = (bytes (mconcat [packIndex a <> packIndex b <> packIndex c | (_, (a, b, c)) <- ts]), 34963, [("componentType", int indexType), ("count", int (3 * length ts)), ("type", string "SCALAR")])
          primitive i (side, ts) = object [("attributes", object [("POSITION", int start)]), ("indices", int i), ("material", int (if side then 0 else 1)), ("extras", object [("materialFaces", array [int (unFaceId fid) | (fid, _) <- ts])])]
          weights = A.toJSON [[A.toJSON [A.toJSON (unVertexId vid), A.toJSON (packedWeight w)] | (vid, w) <- materialWeights v] | v <- vertices]
          mesh = object [("primitives", array [primitive i ch | (i, ch) <- zip [start + 1 ..] (channels ps)]), ("extras", object [("materialWeights", encoded weights)])]
       in (mesh, positionSection : map indexSection (channels ps))
    material name colour = object [("name", string name), ("pbrMetallicRoughness", object [("baseColorFactor", array (let (r, g, b) = linearOf colour in [number r, number g, number b, int 1])), ("metallicFactor", int 0), ("roughnessFactor", int 1)])]

-- Clipping may start the same polygon at a different corner after roundoff.
-- Choose the least packed position as its first corner, preserving winding.
-- Otherwise its fan and metadata change even when its visible region does not.
canonicalPiece :: Double -> PaperPiece -> PaperPiece
canonicalPiece quantum piece = piece {pieceCorners = rotate (pieceCorners piece)}
  where
    rotate corners = case zip [0 ..] corners of
      [] -> []
      first : rest ->
        let (i, _) = foldl' earlier first rest
         in drop i corners ++ take i corners
    earlier old@(_, a) new@(_, b)
      | packable quantum (paperPosition b) < packable quantum (paperPosition a) = new
      | otherwise = old

-- Clipping leaves arithmetic noise in material weights too. Stabilise their
-- metadata at 1e-10, well below the millionth used for positions, or
-- geometrically identical exports differ only in their JSON's last digits.
-- This does not change the display piece or its packed position.
packedWeight :: Double -> Double
packedWeight w = fromInteger (round (w * 1e10)) / 1e10

bounds :: [(Float, Float, Float)] -> ((Float, Float, Float), (Float, Float, Float))
bounds [] = ((0, 0, 0), (0, 0, 0))
bounds (p : ps) = foldl' grow (p, p) ps
  where
    grow ((lx, ly, lz), (hx, hy, hz)) (x, y, z) =
      ((min lx x, min ly y, min lz z), (max hx x, max hy y, max hz z))

-- | Round a length up to a multiple of four.
padded :: Int -> Int
padded n = n + ((4 - n `mod` 4) `mod` 4)

spaces, zeros :: Int -> B.Builder
spaces n = B.string7 (replicate n ' ')
zeros n = mconcat (replicate n (B.word8 0))

-- ---------------------------------------------------------------------------
-- A JSON writer just big enough for one document.
--
-- Hand-rolled for the reason "Senbazuru.Render.Svg" gives for its own output:
-- this is a fixed, small document whose exact bytes are the test contract.
-- aeson would keep the key order it is given; what it would not give is
-- control of how a number is written, and a bound stated as @1.5e-3@ where
-- the data holds a float32 is a validator's disagreement waiting to happen.

object :: [(Text, B.Builder)] -> B.Builder
object fields =
  B.char7 '{'
    <> mconcat (separated [string k <> B.char7 ':' <> v | (k, v) <- fields])
    <> B.char7 '}'

array :: [B.Builder] -> B.Builder
array items = B.char7 '[' <> mconcat (separated items) <> B.char7 ']'

separated :: [B.Builder] -> [B.Builder]
separated [] = []
separated (b : bs) = b : map (B.char7 ',' <>) bs

int :: Int -> B.Builder
int = B.intDec

-- | A float32 written with every digit it has, so that a validator comparing
-- the stated bounds against the packed data finds them equal.
single :: Float -> B.Builder
single f = B.string7 (showFFloat Nothing f "")

triple :: (Float, Float, Float) -> B.Builder
triple (x, y, z) = array (map single [x, y, z])

-- | A colour channel, to four places.
number :: Double -> B.Builder
number d = B.string7 (showFFloat (Just 4) d "")

-- | A string with the five characters JSON cannot take literally escaped, and
-- control characters written as their code. Titles come out of user files.
string :: Text -> B.Builder
string t = B.char7 '"' <> B.byteString (TE.encodeUtf8 (T.concatMap escape t)) <> B.char7 '"'
  where
    escape = \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\r' -> "\\r"
      '\t' -> "\\t"
      c
        | c < ' ' -> T.pack ("\\u" <> pad4 (showHex (fromEnum c) ""))
        | otherwise -> T.singleton c
    pad4 s = replicate (4 - length s) '0' <> s
