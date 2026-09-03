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
-- Unrecognised keys are ignored, which matters in practice: real files carry
-- vendor extensions such as @\"cpedit:page\"@ that we must not choke on.
module Senbazuru.Fold.Types
  ( -- * Documents and frames
    FoldFile (..),
    Frame (..),
    emptyFrame,
    allFrames,

    -- * Element identifiers
    VertexId (..),
    EdgeId (..),
    FaceId (..),

    -- * Edge assignments
    Assignment (..),
    assignmentCode,
    parseAssignment,
  )
where

import Data.Aeson
  ( FromJSON (..),
    Object,
    withObject,
    withText,
    (.!=),
    (.:?),
  )
import Data.Aeson.Types (Parser)
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
    facesVertices :: ![[VertexId]]
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
      facesVertices = []
    }

-- | Every frame in the document, key frame first.
allFrames :: FoldFile -> [Frame]
allFrames f = keyFrame f : otherFrames f

-- | Index into @vertices_*@ arrays.
newtype VertexId = VertexId {unVertexId :: Int}
  deriving stock (Show)
  deriving newtype (Eq, Ord, FromJSON)

-- | Index into @edges_*@ arrays.
newtype EdgeId = EdgeId {unEdgeId :: Int}
  deriving stock (Show)
  deriving newtype (Eq, Ord, FromJSON)

-- | Index into @faces_*@ arrays.
newtype FaceId = FaceId {unFaceId :: Int}
  deriving stock (Show)
  deriving newtype (Eq, Ord, FromJSON)

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
    -- to the frame parser as well.
    keyFrame <- parseFrame o
    otherFrames <- o .:? "file_frames" .!= []
    pure FoldFile {..}

instance FromJSON Frame where
  parseJSON = withObject "FOLD frame" parseFrame

-- | Shared by 'FoldFile' (for the key frame) and 'Frame' (for @file_frames@
-- entries), because in FOLD they are the same set of keys in two places.
parseFrame :: Object -> Parser Frame
parseFrame o = do
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
  pure Frame {..}
