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
-- == The one thing that makes this more than a mesh writer
--
-- __Paper has no thickness, and a depth buffer needs it to.__ Fold a square into
-- quarters and every one of its four faces lands in the same plane — the same
-- @z@, to the last bit. An SVG copes because it paints in an order, and the
-- order is the picture. A 3D renderer does not paint in order; it keeps, at
-- every pixel, whichever triangle is nearest, and when two triangles are at
-- exactly the same depth it keeps whichever one rounding favours. Coincident
-- layers come out as noise, a phenomenon called /z-fighting/, and a flat-folded
-- model is nothing but coincident layers.
--
-- So the layers are given a thickness. Each face is lifted along the sheet's
-- normal by its layer number times a small amount — the layer number being
-- 'Senbazuru.Origami.Layers.layerDepths', the longest chain of faces beneath
-- it, so that four faces stacked come out at heights 0, 1, 2 and 3 and two
-- faces lying side by side come out level. That is how thick paper actually
-- sits: a face with three sheets under it is three sheets up. The amount is a
-- thousandth of the model's size by default, which is about the thickness of
-- paper on a hand-sized square and comfortably more than any depth buffer
-- needs, and a caller may set it — including to zero, which asks for the paper
-- exactly as folded and skips the layer order entirely. A twist, whose layers
-- run in a circle and have no numbers, exports that way and no other.
--
-- Lifting a face means every face has to __own its corners__. Two faces meet
-- along a crease and share its two vertices in the file; lifted to different
-- heights, that shared vertex has to be in two places at once. So the mesh is
-- built with a fresh copy of every corner for every face, and the crease
-- between layers 3 and 7 steps by four thicknesses — which is, again, exactly
-- what a stack of paper does.
--
-- Only a model folded /flat/ is separated this way, for now. Its normal is one
-- direction for the whole sheet, and its layer order is the one thing
-- senbazuru can work out or is given. A form with paper still in the air is
-- written as it stands, and where two of its faces happen to be coplanar they
-- will fight; the general case separates each coplanar group along its own
-- normal and is not built.
--
-- == Two sides, two primitives
--
-- Origami paper is coloured on one side and white on the other, and the export
-- says so. glTF has no notion of a material with two colours, but it culls
-- triangles seen from behind by default, and a triangle's front is decided by
-- the order its corners are listed in. So every face is written twice: once
-- wound as the file has it, in the paper's colour, and once wound the other
-- way, in the underside's. Each copy shows from one side only, and together
-- they are a sheet with a front and a back. The two share one set of positions
-- and differ only in their index lists.
--
-- The winding is the file's, as "Senbazuru.Origami.Layers" takes it, because a
-- face's front /is/ its winding in FOLD. Frames from
-- "Senbazuru.Origami.Folding" are wound counterclockwise on purpose, so their
-- fronts are the side a crease pattern is drawn on.
--
-- No normals are written. The specification requires a viewer to compute flat
-- normals when a mesh carries none, and flat is exactly right for paper.
--
-- == Why this does not go through 'Senbazuru.Diagram'
--
-- Every other backend consumes a 'Senbazuru.Diagram.Diagram', and the
-- architecture says new ones should. A 'Diagram' is two-dimensional — it has
-- 'Senbazuru.Geometry.V2' and no depth — so a 3D exporter is the first thing
-- that genuinely cannot, and this module reads "Senbazuru.Fold.Query"\'s faces
-- directly. That is the stated exception to the rule, chosen over inventing a
-- 3D intermediate representation for a single consumer.
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
    Thickness (..),

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
    FrameKind (..),
    frameFaceOrders,
    frameFaces,
    frameKind,
    frameVertices,
  )
import Senbazuru.Fold.Types (FaceId (..), Frame (..))
import Senbazuru.Geometry.Polygon (isConvex)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, modelSpan, polygonNormal)
import Senbazuru.Geometry.VectorSpace (norm)
import Senbazuru.Origami.Layers (layerDepths, layerOf)
import Senbazuru.Origami.Stacking (Budget, layerOrderFor)
import Senbazuru.Render.Camera (basisFrom, project)

-- | How far apart to place the layers of a flat-folded model.
data Thickness
  = -- | A thousandth of the model's span: paper on a hand-sized square, and
    -- well clear of what any depth buffer can tell apart.
    DefaultThickness
  | -- | Exactly this much, in model units. Zero writes the paper exactly as
    -- folded and asks for no layer order at all, which is the only way to
    -- export a model whose layers run in a circle.
    Thickness !Double
  deriving stock (Eq, Show)

-- | Why a frame could not be written out.
data GltfError
  = -- | The frame itself is unsound, or its layers cannot be stacked. The
    -- error is the frame's own, so that everything a file can be wrong about
    -- reaches a caller as one type.
    GltfRefused !FoldError
  | -- | A face is not convex, and the fan this cuts each face into would
    -- cover paper that is not there. Ear clipping would handle it and is not
    -- built.
    GltfConcaveFace !FaceId
  | -- | Nothing to build: no faces, and no creases to trace any from either.
    GltfNoFaces
  | -- | A thickness that is not a distance: negative, or not a number.
    GltfBadThickness !Double
  | -- | A thickness finer than the rounding the coordinates go through, which
    -- would lift some layers by a step and others by none. Carries the
    -- thickness asked for and the finest one this model can hold.
    GltfThicknessTooFine !Double !Double
  | -- | A coordinate that single precision cannot hold: not a number, or
    -- beyond about 3.4e38. Written through, it would arrive as the bare token
    -- @Infinity@ in the JSON, which no parser accepts.
    GltfUnwritableCoordinate !Double
  deriving stock (Eq, Show)

instance Explain GltfError where
  explain = \case
    -- The frame's own message is about painting, which is what the layer order
    -- was first for; here it is about height, and the reader has a way out.
    GltfRefused (ImpossibleStacking (FaceId f)) ->
      "the layers run in a circle through face "
        <> tshow f
        <> ", so there is no height to lift each face to; with a thickness of"
        <> " zero the model is written exactly as folded, circle and all"
    GltfRefused err -> explain err
    GltfConcaveFace (FaceId f) ->
      "face "
        <> tshow f
        <> " is not convex, and a 3D model is built from triangles fanned out"
        <> " from each face's first corner, which is only right for convex faces"
    GltfNoFaces -> "there are no creases here, so there is no surface to write"
    -- 'tshow' and not 'num' for the four numbers below, although every one of
    -- them is a distance. Three are the thickness the user typed, and quoting
    -- it back the way @show@ writes it is what lets them match the message
    -- against their own command line; @num@ would answer @--thickness 0.001@
    -- with @1.000000e-3@. 'GltfThicknessTooFine' then prints @finest@ beside
    -- it, and two numbers meant to be compared have to be written the same way.
    GltfBadThickness t ->
      "a thickness of " <> tshow t <> " is not a distance"
    GltfThicknessTooFine t finest ->
      "a thickness of "
        <> tshow t
        <> " is finer than the rounding this model's coordinates go through,"
        <> " which is "
        <> tshow finest
        <> "; some layers would be lifted and others not"
    GltfUnwritableCoordinate c ->
      "the coordinate " <> tshow c <> " cannot be written in single precision"

-- | 'explain' for a 'GltfError', under the name call sites already use.
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
renderGlb :: Budget -> Thickness -> Maybe Text -> Frame -> Either GltfError ByteString
renderGlb budget thickness name fr0 = do
  -- The same tracing "Senbazuru.Origami.Folding" does, and here for the same
  -- reason it takes a --layer-budget: a policy that reaches only one backend
  -- is a policy that is wrong on the other. A crease pattern that records no
  -- faces still has them, and exporting a flat sheet is a thing to be able to
  -- do with one.
  fr <- refused (withPlanarFaces fr0)
  verts <- refused (frameVertices fr)
  faces <- refused (frameFaces fr)
  _ <- refused (frameFaceOrders fr)
  if null faces then Left GltfNoFaces else Right ()
  mapM_ writable verts
  let span' = modelSpan verts
      quantum = quantumFor span'
      -- The same rule "Senbazuru.Origami.Flat" uses for a face with no area,
      -- over the model's size in any direction rather than in the plane, since
      -- a face here may lie in any plane: a hair wide and as long as the
      -- model. Computed once, not once per face.
      speck = 1e-9 * max 1 span' * max 1 span'
  step <- resolve thickness span' quantum
  layer <- layersFor budget step fr verts faces
  mapM_ (convexOrRefuse speck) faces
  let corners f = [toGltfAxes (lift (fromIntegral (layer (faceId f)) * step) c) | c <- faceCorners f]
  pure (assemble name [(faceId f, map (packable quantum) (corners f)) | f <- faces])
  where
    refused :: Either FoldError a -> Either GltfError a
    refused = first GltfRefused

    lift dz (V3 x y z) = V3 x y (z + dz)

    writable (V3 x y z) = mapM_ component [x, y, z]
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

-- | The thickness to use, as a number.
--
-- A thickness finer than the rounding step is refused rather than rounded
-- away: rounded, some layers would land a step apart and others on the same
-- height, and a face might even straddle two rounding cells and kink. The
-- default is a thousand steps, so it never comes near.
resolve :: Thickness -> Double -> Double -> Either GltfError Double
resolve thickness span' quantum = case thickness of
  DefaultThickness -> Right (span' / 1000)
  Thickness t
    | isNaN t || isInfinite t || t < 0 -> Left (GltfBadThickness t)
    | t > 0 && t < quantum -> Left (GltfThicknessTooFine t quantum)
    | otherwise -> Right t

-- | Each face's layer number, or zero for every face when there is nothing to
-- separate: a thickness of zero, a crease pattern, a model with paper in the
-- air, or one whose layers the solver declines to order.
--
-- A crease pattern is decided the way "Senbazuru.Render.CreasePattern" decides
-- it, by 'frameKind', and never reaches the solver. Its faces do not overlap,
-- so there is nothing to order — and the solver, asked anyway, would refuse a
-- file with a face wound backwards or a short @edges_foldAngle@, both of which
-- @render@ draws without complaint. A flag deciding which files are acceptable
-- is the failure that module was rewritten to avoid.
--
-- Declining is not refusing. A flat model with a concave face is one the
-- solver does not cover, and it comes back unseparated here so that the
-- convexity check can refuse it with the right message rather than this one
-- refusing it with a message about layers.
layersFor :: Budget -> Double -> Frame -> [V3] -> [Face] -> Either GltfError (FaceId -> Int)
layersFor budget step fr verts faces
  | step == 0 || hasRelief verts = Right (const 0)
  | frameKind (frameClasses fr) verts == CreasePattern = Right (const 0)
  | otherwise = do
      -- The whole frame, not the vertices and faces already in hand: the solver
      -- reads the creases and their assignments, which is where every rule
      -- about which layer can go where comes from. The first version rebuilt a
      -- frame from the faces alone and the solver, finding no creases, found
      -- nothing to constrain -- and stacked every model flat.
      ordering <- first GltfRefused (layerOrderFor budget fr)
      case ordering of
        Nothing -> Right (const 0)
        Just orders -> do
          -- Numbered from the +z side, so that layer zero is the sheet on the
          -- table and the stack rises out of it. There is no viewer here to
          -- ask; +z is where FOLD says up is.
          depths <- first GltfRefused (layerDepths (V3 0 0 1) faces orders)
          Right (layerOf depths)

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

-- | The whole document: a header, the JSON chunk, the binary chunk.
--
-- Every face arrives with its own corners already placed, and this decides
-- nothing about geometry. It lays the corners out one after another in the
-- position buffer, fans each face into triangles by index, writes the fans
-- once forwards and once reversed, and wraps the lot.
assemble :: Maybe Text -> [(FaceId, [(Float, Float, Float)])] -> ByteString
assemble title faces =
  BL.toStrict . B.toLazyByteString $
    B.string7 "glTF"
      <> B.word32LE 2
      <> B.word32LE (fromIntegral total)
      <> chunk "JSON" spaces jsonBytes
      <> chunk "BIN\0" zeros binBytes
  where
    positions = concatMap snd faces
    vertexCount = length positions

    -- Where each face's corners start in the position buffer.
    starts = scanl (+) 0 [length cs | (_, cs) <- faces]

    -- A fan from each face's first corner, and the same fan wound the other
    -- way. Reversing the two later corners is what turns the triangle over:
    -- its front is on the side its corners go round anticlockwise from.
    front = concat [fan start (length cs) | (start, (_, cs)) <- zip starts faces]
    back = map turnOver front
    fan start n = [(start, start + i, start + i + 1) | i <- [1 .. n - 2]]
    turnOver (a, b, c) = (a, c, b)
    indexCount = 3 * length front

    -- Sixteen-bit indices unless the model is too big for them, which no
    -- origami model is but a file could be.
    wide = vertexCount > 65535
    indexType, indexSize :: Int
    indexType = if wide then 5125 else 5123
    indexSize = if wide then 4 else 2
    packIndex i = if wide then B.word32LE (fromIntegral i) else B.word16LE (fromIntegral i)
    packTriangles ts = mconcat [packIndex a <> packIndex b <> packIndex c | (a, b, c) <- ts]

    positionBytes = 12 * vertexCount
    indexBytes = indexSize * indexCount
    positionsOffset = 0
    frontOffset = positionsOffset + positionBytes
    backOffset = frontOffset + padded indexBytes
    binLength = backOffset + padded indexBytes

    binBytes =
      BL.toStrict . B.toLazyByteString $
        mconcat [B.floatLE x <> B.floatLE y <> B.floatLE z | (x, y, z) <- positions]
          <> packTriangles front
          <> zeros (padded indexBytes - indexBytes)
          <> packTriangles back
          <> zeros (padded indexBytes - indexBytes)

    jsonBytes = BL.toStrict (B.toLazyByteString json)

    -- Each chunk is padded to the four-byte boundary the specification
    -- requires, with the filler it requires: spaces for JSON, zeros for binary.
    chunk tag filler bytes =
      B.word32LE (fromIntegral (padded (BS.length bytes)))
        <> B.string7 tag
        <> B.byteString bytes
        <> filler (padded (BS.length bytes) - BS.length bytes)

    total = 12 + 8 + padded (BS.length jsonBytes) + 8 + padded (BS.length binBytes)

    (lo, hi) = bounds positions

    json =
      object
        [ ("asset", object [("version", string "2.0"), ("generator", string "senbazuru")]),
          ("scene", int 0),
          ("scenes", array [object [("nodes", array [int 0])]]),
          ("nodes", array [object (("mesh", int 0) : [("name", string t) | Just t <- [title]])]),
          ( "meshes",
            array
              [ object
                  [ ( "primitives",
                      array
                        [ primitive 1 0,
                          primitive 2 1
                        ]
                    )
                  ]
              ]
          ),
          ( "materials",
            array
              [ material "paper" paper,
                material "paper underside" paperUnderside
              ]
          ),
          ( "accessors",
            array
              [ object
                  [ ("bufferView", int 0),
                    ("componentType", int 5126),
                    ("count", int vertexCount),
                    ("type", string "VEC3"),
                    ("min", triple lo),
                    ("max", triple hi)
                  ],
                indexAccessor 1,
                indexAccessor 2
              ]
          ),
          ( "bufferViews",
            array
              [ view positionsOffset positionBytes 34962,
                view frontOffset indexBytes 34963,
                view backOffset indexBytes 34963
              ]
          ),
          ("buffers", array [object [("byteLength", int binLength)]])
        ]

    primitive indices materialIx =
      object
        [ ("attributes", object [("POSITION", int 0)]),
          ("indices", int indices),
          ("material", int materialIx)
        ]

    -- Matte paper: no metal, fully rough, and culled from behind so that the
    -- other copy of the face can show its other colour.
    material name colour =
      object
        [ ("name", string name),
          ( "pbrMetallicRoughness",
            object
              [ ("baseColorFactor", array (let (r, g, b) = linearOf colour in [number r, number g, number b, int 1])),
                ("metallicFactor", int 0),
                ("roughnessFactor", int 1)
              ]
          )
        ]

    indexAccessor viewIx =
      object
        [ ("bufferView", int viewIx),
          ("componentType", int indexType),
          ("count", int indexCount),
          ("type", string "SCALAR")
        ]

    view offset len target =
      object
        [ ("buffer", int 0),
          ("byteOffset", int offset),
          ("byteLength", int len),
          ("target", int target)
        ]

    triple (x, y, z) = array [single x, single y, single z]

-- | The smallest and largest of each coordinate, which a @POSITION@ accessor
-- is required to state. The list is never empty here: 'renderGlb' refuses a
-- frame with no faces before this is reached, and a face has three corners at
-- least.
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
