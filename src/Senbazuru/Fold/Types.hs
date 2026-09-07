-- |
-- Module      : Senbazuru.Fold.Types
-- Description : A faithful in-memory mirror of the FOLD 1.2 file format.
--
-- <https://github.com/edemaine/FOLD/blob/main/doc/spec.md>
--
-- == What FOLD actually is
--
-- A @.fold@ file is JSON describing a /planar graph/ drawn on a sheet of
-- paper: vertices with coordinates, edges between them, and faces bounded by
-- those edges. Each edge carries an assignment saying how the paper folds
-- there. That is the whole idea; the rest is bookkeeping.
--
-- Keys follow an @object_property@ convention, and every @X_Y@ key is an array
-- indexed by @X@ id. So @edges_assignment[7]@ is the assignment of edge 7.
-- Ids are zero-based indices into these parallel arrays — there is no
-- @\"id\"@ field anywhere.
--
-- == Why these types are so permissive
--
-- Almost every field here is a 'Maybe' or a possibly-empty list, and
-- @vertices_coords@ is typed as @[[Double]]@ rather than @[V2]@. That is
-- deliberate. FOLD says nearly all keys are optional, coordinates may be 2D or
-- 3D, and the parallel arrays are not guaranteed to have matching lengths.
--
-- These types therefore answer only \"what does the file say?\". The question
-- \"is this a well-formed 2D crease pattern?\" is answered separately in
-- "Senbazuru.Fold.Query", which turns the loose shape into a strict one and
-- reports precisely what was wrong when it cannot. Keeping the two apart means
-- a decode failure always means \"this is not valid JSON-shaped FOLD\", never
-- \"this is FOLD that I happen to not support yet\".
--
-- Unrecognised keys are not interpreted, which matters in practice: real files
-- carry vendor extensions such as @\"cpedit:page\"@ that we must not choke on.
-- They are not thrown away either — see below.
--
-- == Writing a file back out
--
-- The 'ToJSON' instances here invert the 'FromJSON' ones, and are deliberately
-- careful about what they put on the page.
--
-- __A field that was absent stays absent.__ An empty @faces_vertices@ that we
-- invented is not the file we were handed, and a reader that tells \"this model
-- has no faces\" apart from \"this file does not record faces\" would be told
-- something untrue. So a 'Nothing', an empty list, and a @frame_inherit@ of
-- 'False' are all simply not written.
--
-- __Keys we do not understand are kept.__ They are collected verbatim into
-- 'frameExtras' on the way in and written back where they came from. Dropping
-- them would make senbazuru a bad citizen in a toolchain: FOLD namespaces
-- vendor extensions with a colon precisely so that they can survive a tool
-- that does not read them, and the rest — @vertices_edges@, @edgeOrders@ —
-- is the part of the specification we have not implemented, which is no better
-- a thing to destroy. The price is that a transform which /invalidates/ one has
-- to say so; \"Senbazuru.Origami.Folding\" is the one that does.
--
-- __Keys come out in the order the specification lists them__, with a frame's
-- unknown keys sorted and placed after its known ones, so that the output is
-- byte-for-byte reproducible and a diff between two files is readable.
module Senbazuru.Fold.Types
  ( -- * Documents and frames
    FoldFile (..),
    Frame (..),
    emptyFrame,
    allFrames,
    replacingFrame,

    -- * Element identifiers
    VertexId (..),
    EdgeId (..),
    FaceId (..),

    -- * Edge assignments
    Assignment (..),
    assignmentCode,
    parseAssignment,

    -- * Layer ordering
    FaceOrder (..),
    Stacking (..),
    stackingSign,

    -- * The keys senbazuru understands
    fileKeys,
    frameKeys,
  )
where

import Data.Aeson
  ( FromJSON (..),
    Key,
    Object,
    Series,
    ToJSON (..),
    object,
    pairs,
    withArray,
    withObject,
    withText,
    (.!=),
    (.:?),
    (.=),
  )
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Pair, Parser)
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as T

-- | A whole @.fold@ document.
--
-- Note the slightly surprising shape of the format: the top-level JSON object
-- is /both/ the file metadata /and/ the first frame (\"the key frame\").
-- Additional frames live in @file_frames@. We split that apart on decode so
-- that callers never have to remember it.
data FoldFile = FoldFile
  { -- | @file_spec@. A number, not an integer: files in the wild say @1.1@.
    fileSpec :: !(Maybe Double),
    fileCreator :: !(Maybe Text),
    fileAuthor :: !(Maybe Text),
    fileTitle :: !(Maybe Text),
    fileDescription :: !(Maybe Text),
    -- | @file_classes@, e.g. @[\"singleModel\"]@ or @[\"diagrams\"]@.
    fileClasses :: ![Text],
    -- | The frame stored inline at the top level.
    keyFrame :: !Frame,
    -- | @file_frames@: every frame after the key frame.
    otherFrames :: ![Frame]
  }
  deriving stock (Eq, Show)

-- | One frame: a single state of the paper.
--
-- A crease pattern (@frame_classes: [\"creasePattern\"]@) is the flat, unfolded
-- sheet with its creases marked. A folded form
-- (@frame_classes: [\"foldedForm\"]@) is the same graph with vertices moved to
-- where they end up after folding, usually in 3D. A multi-frame file is how
-- FOLD represents a sequence of diagram steps.
data Frame = Frame
  { frameAuthor :: !(Maybe Text),
    frameTitle :: !(Maybe Text),
    frameDescription :: !(Maybe Text),
    frameClasses :: ![Text],
    -- | @frame_attributes@, e.g. @\"2D\"@, @\"3D\"@, @\"orientable\"@.
    frameAttributes :: ![Text],
    -- | @frame_unit@: @\"unit\"@, @\"mm\"@, @\"in\"@, and so on.
    frameUnit :: !(Maybe Text),
    frameParent :: !(Maybe Int),
    -- | @frame_inherit@. Note: resolving inheritance is not implemented yet;
    -- this field is currently decoded and carried, not acted upon.
    frameInherit :: !Bool,
    -- | @vertices_coords@, indexed by 'VertexId'. Each inner list is 2 or 3
    -- numbers. Left unrefined on purpose — see the module header.
    verticesCoords :: ![[Double]],
    -- | @edges_vertices@, indexed by 'EdgeId'. The tuple type makes aeson reject
    -- an edge that does not have exactly two endpoints, which is one class of
    -- malformed file caught for free.
    edgesVertices :: ![(VertexId, VertexId)],
    -- | @edges_assignment@, indexed by 'EdgeId'.
    edgesAssignment :: ![Assignment],
    -- | @edges_foldAngle@ in degrees, in @[-180, 180]@. Indexed by 'EdgeId'.
    edgesFoldAngle :: ![Double],
    -- | @faces_vertices@, indexed by 'FaceId', counterclockwise around the face.
    facesVertices :: ![[VertexId]],
    -- | @faceOrders@: which face is on top where the model overlaps itself.
    -- Unindexed — this is a list of relationships, not a parallel array.
    faceOrders :: ![FaceOrder],
    -- | Every key of this frame's object that senbazuru does not understand,
    -- kept exactly as it arrived so that writing the file out again does not
    -- destroy it. Both vendor extensions such as @\"cpedit:page\"@ and the
    -- parts of the specification not implemented here, such as
    -- @vertices_edges@, end up in it.
    --
    -- For the key frame this holds the unknown keys of the /top-level/ object,
    -- since that object /is/ the key frame. See 'parseFrame'.
    --
    -- Anything building a 'Frame' by hand should leave this alone. A key here
    -- that the encoder also writes — one of 'frameKeys', or one of 'fileKeys'
    -- on the key frame — loses to the field, and is not written at all.
    frameExtras :: !Object
  }
  deriving stock (Eq, Show)

-- | A frame with no geometry and no metadata. Useful as a base for tests and
-- for building frames field by field.
emptyFrame :: Frame
emptyFrame =
  Frame
    { frameAuthor = Nothing,
      frameTitle = Nothing,
      frameDescription = Nothing,
      frameClasses = [],
      frameAttributes = [],
      frameUnit = Nothing,
      frameParent = Nothing,
      frameInherit = False,
      verticesCoords = [],
      edgesVertices = [],
      edgesAssignment = [],
      edgesFoldAngle = [],
      facesVertices = [],
      faceOrders = [],
      frameExtras = KM.empty
    }

-- | Every frame in the document, key frame first.
allFrames :: FoldFile -> [Frame]
allFrames f = keyFrame f : otherFrames f

-- | The document with the nth frame replaced, counting the way 'allFrames'
-- counts: the key frame is 0 and @file_frames@ start at 1.
--
-- Lives here beside 'allFrames' rather than in whatever wants it, because the
-- two are one numbering written twice. The key frame is stored inline at the
-- top level and the rest are in a list, so reading the nth and writing the nth
-- are each a small index shift — and two independent shifts of the same
-- numbering is how a verb ends up writing into the wrong frame in silence.
--
-- An index no frame has leaves the document alone. The caller that took a
-- frame out by the same index has already been told there is no such frame.
replacingFrame :: Int -> Frame -> FoldFile -> FoldFile
replacingFrame index frame f
  | index == 0 = f {keyFrame = frame}
  | otherwise =
      f
        { otherFrames =
            [ if i == index then frame else other
              | (i, other) <- zip [1 ..] (otherFrames f)
            ]
        }

-- | Index into @vertices_*@ arrays.
newtype VertexId = VertexId {unVertexId :: Int}
  deriving stock (Show)
  deriving newtype (Eq, Ord, FromJSON, ToJSON)

-- | Index into @edges_*@ arrays.
newtype EdgeId = EdgeId {unEdgeId :: Int}
  deriving stock (Show)
  deriving newtype (Eq, Ord, FromJSON, ToJSON)

-- | Index into @faces_*@ arrays.
newtype FaceId = FaceId {unFaceId :: Int}
  deriving stock (Show)
  deriving newtype (Eq, Ord, FromJSON, ToJSON)

-- | How the paper behaves along an edge.
--
-- Mountain and valley are the two real folds and are mirror images of each
-- other: with the sheet flat on a table, a mountain crease rises towards you
-- and a valley crease sinks away. Which one an edge is depends on which side
-- of the paper you are looking at — flip the sheet over and every mountain
-- becomes a valley.
data Assignment
  = -- | @B@ — boundary of the sheet. Not a fold; the edge of the paper.
    Border
  | -- | @M@ — mountain fold, fold angle in @[-180, 0)@.
    Mountain
  | -- | @V@ — valley fold, fold angle in @(0, 180]@.
    Valley
  | -- | @F@ — flat: a crease line that is not folded (angle 0).
    Flat
  | -- | @U@ — unassigned: a crease whose direction is not yet decided.
    Unassigned
  | -- | @C@ — cut/slit in the paper.
    Cut
  | -- | @J@ — join: the two incident faces are really one (FOLD 1.2+).
    Join
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The single-letter code used in @edges_assignment@.
assignmentCode :: Assignment -> Text
assignmentCode = \case
  Border -> "B"
  Mountain -> "M"
  Valley -> "V"
  Flat -> "F"
  Unassigned -> "U"
  Cut -> "C"
  Join -> "J"

-- | Where one face sits relative to another's normal.
--
-- The direction is the /other/ face's normal, not the viewer's: FOLD records
-- how the paper is stacked, which is a fact about the model, and turning that
-- into a drawing order needs a viewing direction as well. See
-- "Senbazuru.Origami.Layers".
data Stacking
  = -- | On the side the other face's normal points to.
    Above
  | -- | On the side away from it.
    Below
  | -- | Not ordered, which a file says when two faces do not overlap in their
    -- interiors and so cannot obscure one another.
    Unordered
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | One entry of @faceOrders@: the triple @[f, g, s]@.
--
-- @s@ is read relative to __@g@'s__ normal, and a face's normal is defined by
-- the counterclockwise ordering of its own @faces_vertices@. So unlike
-- everywhere else in senbazuru, the winding a file states is not merely
-- advisory here — it is what gives these signs their meaning, and it has to be
-- taken as given rather than recomputed.
data FaceOrder = FaceOrder
  { -- | @f@, the face being placed.
    orderFace :: !FaceId,
    -- | @g@, the face it is placed relative to, and whose normal fixes the
    -- sense of 'orderStacking'.
    orderRelativeTo :: !FaceId,
    orderStacking :: !Stacking
  }
  deriving stock (Eq, Show)

instance FromJSON FaceOrder where
  parseJSON = withArray "faceOrders entry" $ \v -> case toList v of
    [f, g, s] -> do
      orderFace <- parseJSON f
      orderRelativeTo <- parseJSON g
      orderStacking <- parseJSON s >>= toStacking
      pure FaceOrder {..}
    other ->
      fail ("faceOrders entry must be [f, g, s], but has " <> show (length other) <> " elements")
    where
      toStacking :: Int -> Parser Stacking
      toStacking = \case
        1 -> pure Above
        -1 -> pure Below
        0 -> pure Unordered
        n -> fail ("faceOrders sign must be -1, 0 or 1, not " <> show n)

-- | The @s@ of a @faceOrders@ triple: the inverse of the table above.
stackingSign :: Stacking -> Int
stackingSign = \case
  Above -> 1
  Below -> -1
  Unordered -> 0

-- | Parse an @edges_assignment@ code.
--
-- The spec uses uppercase, but lowercase codes appear in files produced by
-- some tools, so both are accepted.
parseAssignment :: Text -> Maybe Assignment
parseAssignment t = case T.toUpper (T.strip t) of
  "B" -> Just Border
  "M" -> Just Mountain
  "V" -> Just Valley
  "F" -> Just Flat
  "U" -> Just Unassigned
  "C" -> Just Cut
  "J" -> Just Join
  _ -> Nothing

instance FromJSON Assignment where
  parseJSON = withText "edge assignment" $ \t ->
    case parseAssignment t of
      Just a -> pure a
      Nothing ->
        fail $
          "unknown edge assignment "
            <> show t
            <> "; expected one of B, M, V, F, U, C, J"

instance FromJSON FoldFile where
  parseJSON = withObject "FOLD file" $ \o -> do
    fileSpec <- o .:? "file_spec"
    fileCreator <- o .:? "file_creator"
    fileAuthor <- o .:? "file_author"
    fileTitle <- o .:? "file_title"
    fileDescription <- o .:? "file_description"
    fileClasses <- o .:? "file_classes" .!= []
    -- The top-level object doubles as the key frame, so the same Object is fed
    -- to the frame parser as well — telling it which keys have already been
    -- taken, so that it does not file @file_spec@ under 'frameExtras'.
    keyFrame <- parseFrame fileKeys o
    otherFrames <- o .:? "file_frames" .!= []
    pure FoldFile {..}

instance FromJSON Frame where
  parseJSON = withObject "FOLD frame" (parseFrame [])

-- | The keys 'FoldFile' reads for itself: the ones that mean something only at
-- the top level.
fileKeys :: [Key]
fileKeys =
  [ "file_spec",
    "file_creator",
    "file_author",
    "file_title",
    "file_description",
    "file_classes",
    "file_frames"
  ]

-- | The keys 'parseFrame' reads, which are also exactly the keys 'framePairs'
-- writes.
--
-- Neither of those can derive the list, so it is stated once here and used by
-- both: the parser subtracts it to find what it did not understand, and the
-- encoder subtracts it again to make sure nothing it understands can be
-- written a second time out of 'frameExtras'.
--
-- "Senbazuru.Fold.TypesSpec" checks the list against the encoder — writing a
-- document with every field set has to produce exactly these keys and no
-- others. The other direction, that everything written is read back, is what
-- the generated round trip there tests.
frameKeys :: [Key]
frameKeys =
  [ "frame_author",
    "frame_title",
    "frame_description",
    "frame_classes",
    "frame_attributes",
    "frame_unit",
    "frame_parent",
    "frame_inherit",
    "vertices_coords",
    "edges_vertices",
    "edges_assignment",
    "edges_foldAngle",
    "faces_vertices",
    "faceOrders"
  ]

-- | Shared by 'FoldFile' (for the key frame) and 'Frame' (for @file_frames@
-- entries), because in FOLD they are the same set of keys in two places.
--
-- @claimed@ is what the caller has already taken for itself: 'fileKeys' for
-- the top-level object, nothing for a @file_frames@ entry. Whatever is left
-- after those and 'frameKeys' is what we do not understand, and it is kept
-- verbatim in 'frameExtras' rather than dropped.
parseFrame :: [Key] -> Object -> Parser Frame
parseFrame claimed o = do
  frameAuthor <- o .:? "frame_author"
  frameTitle <- o .:? "frame_title"
  frameDescription <- o .:? "frame_description"
  frameClasses <- o .:? "frame_classes" .!= []
  frameAttributes <- o .:? "frame_attributes" .!= []
  frameUnit <- o .:? "frame_unit"
  frameParent <- o .:? "frame_parent"
  frameInherit <- o .:? "frame_inherit" .!= False
  verticesCoords <- o .:? "vertices_coords" .!= []
  edgesVertices <- o .:? "edges_vertices" .!= []
  edgesAssignment <- o .:? "edges_assignment" .!= []
  edgesFoldAngle <- o .:? "edges_foldAngle" .!= []
  facesVertices <- o .:? "faces_vertices" .!= []
  faceOrders <- o .:? "faceOrders" .!= []
  let frameExtras = foldr KM.delete o (claimed <> frameKeys)
  pure Frame {..}

instance ToJSON Assignment where
  toJSON = toJSON . assignmentCode
  toEncoding = toEncoding . assignmentCode

instance ToJSON FaceOrder where
  toJSON o = toJSON (orderFace o, orderRelativeTo o, stackingSign (orderStacking o))
  toEncoding o = toEncoding (orderFace o, orderRelativeTo o, stackingSign (orderStacking o))

instance ToJSON Frame where
  toJSON = object . framePairs []
  toEncoding = pairs . series . framePairs []

instance ToJSON FoldFile where
  toJSON = object . filePairs
  toEncoding = pairs . series . filePairs

-- | The keys of a whole document, in the order the specification lists them.
--
-- The key frame's own keys sit in the middle, between the file metadata and
-- @file_frames@, because that is where they live in the file: the top-level
-- object is both. This is the only place in the library that has to know it.
filePairs :: FoldFile -> [Pair]
filePairs FoldFile {..} =
  concat
    [ omitNothing "file_spec" fileSpec,
      omitNothing "file_creator" fileCreator,
      omitNothing "file_author" fileAuthor,
      omitNothing "file_title" fileTitle,
      omitNothing "file_description" fileDescription,
      omitEmpty "file_classes" fileClasses,
      framePairs fileKeys keyFrame,
      omitEmpty "file_frames" otherFrames
    ]

-- | The keys of one frame, in the order the specification lists them, with
-- 'frameExtras' after them.
--
-- The key names written here must be exactly 'frameKeys' — see the note there.
--
-- @claimed@ mirrors 'parseFrame': 'fileKeys' when this frame is the key frame
-- and the object it is being written into is also the file, nothing when it is
-- a @file_frames@ entry. Together with 'frameKeys' it is what 'frameExtras' is
-- filtered against on the way out, so that a frame carrying an extra the
-- encoder also writes emits that key once rather than twice. The decoder can
-- never produce such a frame — it subtracts the same keys — but a caller
-- building one by hand can, and a JSON object with a repeated key is read
-- differently by different tools, which is the one thing a format written for
-- interchange must not do.
framePairs :: [Key] -> Frame -> [Pair]
framePairs claimed Frame {..} =
  concat
    [ omitNothing "frame_author" frameAuthor,
      omitNothing "frame_title" frameTitle,
      omitNothing "frame_description" frameDescription,
      omitEmpty "frame_classes" frameClasses,
      omitEmpty "frame_attributes" frameAttributes,
      omitNothing "frame_unit" frameUnit,
      omitNothing "frame_parent" frameParent,
      omitFalse "frame_inherit" frameInherit,
      omitEmpty "vertices_coords" verticesCoords,
      omitEmpty "edges_vertices" edgesVertices,
      omitEmpty "edges_assignment" edgesAssignment,
      omitEmpty "edges_foldAngle" edgesFoldAngle,
      omitEmpty "faces_vertices" facesVertices,
      omitEmpty "faceOrders" faceOrders,
      -- Sorted, so that two runs of senbazuru over the same file produce the
      -- same bytes. A KeyMap has no order of its own to inherit.
      KM.toAscList (foldr KM.delete frameExtras (claimed <> frameKeys))
    ]

-- | Keep an ordered list of pairs ordered on the way out.
--
-- 'object' would lose it — an 'Object' is a hash map — so the instances above
-- define 'toEncoding' as well, which is what 'Data.Aeson.encode' actually
-- uses, and build it from a 'Series', which concatenates in order.
--
-- Note what going through 'Pair' — that is, through 'Data.Aeson.Value' — buys
-- on the way: 'toJSON' of a 'Double' rounds through 'Scientific', whose
-- coefficient is an 'Integer' and so has no sign to keep, and @-0.0@ comes out
-- as @0@. 'toEncoding' of a 'Double' does not: it writes @-0.0@. Folding
-- produces negative zeros, so building the 'Series' straight from 'toEncoding'
-- to save the intermediate 'Value' would put them back into written files.
-- "Senbazuru.Fold.TypesSpec" pins this.
series :: [Pair] -> Series
series = foldMap (uncurry (.=))

-- | Write a key only if the field has a value. See the module header: an
-- absent key and a key written as @null@ are not the same file.
omitNothing :: (ToJSON a) => Key -> Maybe a -> [Pair]
omitNothing k = maybe [] (\v -> [k .= v])

-- | Write a key only if the list has something in it.
omitEmpty :: (ToJSON a) => Key -> [a] -> [Pair]
omitEmpty _ [] = []
omitEmpty k xs = [k .= xs]

-- | Write a flag only when it is set, because absent means 'False' already.
omitFalse :: Key -> Bool -> [Pair]
omitFalse k b = [k .= True | b]
