-- |
-- Module      : Senbazuru.Import.Segments
-- Description : Turning a bare list of creases into a FOLD frame.
--
-- Most crease patterns in the wild are not FOLD files. The two formats the
-- desktop editors have used for twenty years — Orihime and Oriedita's @.cp@,
-- ORIPA's @.opx@ — both store the same thing: a flat list of line segments,
-- each with a code saying what kind of line it is. There is no vertex list, no
-- face list and no connectivity at all. "Senbazuru.Import.Cp" and
-- "Senbazuru.Import.Opx" do the two file formats; everything they have in
-- common is here.
--
-- == Why a segment list is not a graph
--
-- FOLD stores a /planar graph/: numbered vertices, and edges that name two of
-- them. Two creases meeting at a corner say so, because they name the same
-- vertex id. A segment list says nothing of the kind. Two creases meet at a
-- corner only in the weaker sense that one segment's endpoint has the same
-- coordinates as another's, and \"the same coordinates\" is a statement about
-- 'Double's that real files do not quite satisfy. Six creases meet at the
-- centre of Oriedita's own bird base, and it spells that one point three
-- different ways:
--
-- > 9.094947017729283E-15   9.094947017729283E-15
-- > 9.094947017729283E-15  -0.0
-- > 1.2246467991473534E-14  9.094947017729283E-15
--
-- because it computed those points by reflecting other points across creases
-- and never rounded. All three are the origin, and the file's 52 endpoints are
-- 22 distinct spellings of 13 vertices. Rebuilding that vertex list — deciding
-- which endpoints are one point — is therefore the whole job of this module,
-- and it needs a tolerance.
--
-- == The tolerance
--
-- 'mergeTolerance' is a billionth of the pattern's own diagonal: @5.66e-7@ for
-- the 400-unit square both editors draw on. That is about ten million times
-- larger than the error above and about ten million times smaller than any
-- feature a person would draw, which is the comfortable middle a relative
-- tolerance is for. An absolute one could not be: the same reader has to cope
-- with a pattern on the unit square and one on a 400-unit square.
--
-- Endpoints are matched through a grid of cells one tolerance wide, so that
-- finding the candidates near a point does not mean scanning every point found
-- so far. Note that a grid alone will not do the job — rounding each
-- coordinate to a cell and calling equal cells equal splits any pair that
-- happens to straddle a cell boundary, which is exactly the pair that needs
-- merging most. The grid only narrows the search; the distance decides.
--
-- == Which way up
--
-- Both formats were written by Java desktop applications and store /screen/
-- coordinates, where @y@ increases downwards. Senbazuru's model space has @y@
-- increasing upwards, so 'fromScreenPoint' negates it on the way in. See that
-- function for why this is not optional.
module Senbazuru.Import.Segments
  ( -- * Segments
    Segment (..),
    fromScreenPoint,

    -- * What can be wrong with one
    ImportError (..),
    renderImportError,

    -- * Building a frame
    mergeTolerance,
    frameFromSegments,
    foldFileFromSegments,
  )
where

import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Fold.Types
  ( Assignment,
    FoldFile (..),
    Frame (..),
    VertexId (..),
    emptyFrame,
  )
import Senbazuru.Geometry (V2 (..), boxFromPoints, boxSize, norm, (^-^))

-- | One line of a @.cp@ file, or one @OriLineProxy@ of an @.opx@ file: two
-- endpoints and what kind of line joins them.
--
-- 'segLine' is the line of the source file this came from, counted from 1 as
-- an editor counts. It is carried so that a complaint can point at the
-- offending line rather than at the file: someone holding a 4000-line crease
-- pattern is not helped by \"malformed\".
data Segment = Segment
  { segLine :: !Int,
    segStart :: !V2,
    segEnd :: !V2,
    segAssignment :: !Assignment
  }
  deriving stock (Eq, Show)

-- | A point as the editors that write these formats store one: @x@ to the
-- right, @y@ /downwards/.
--
-- Negating @y@ is not a matter of taste. A crease pattern read upside down is
-- not the same model drawn differently — it is the mirror image, which is a
-- different model, folded from the other side of the paper. (Mirroring a
-- pattern without also swapping every mountain for a valley gives the
-- reflection of what the author drew.) Senbazuru is @y@-up throughout, so the
-- conversion happens once, here, at the point where the file's convention is
-- still in scope.
--
-- Oriedita's own FOLD /export/ does not do this, so a @.cp@ read by senbazuru
-- and the same @.cp@ passed through Oriedita's FOLD exporter come out as
-- mirror images of each other. Ours is the one that matches the drawing on
-- Oriedita's screen.
fromScreenPoint :: Double -> Double -> V2
fromScreenPoint x y = V2 x (negate y)

-- | Everything that can be wrong with a @.cp@ or an @.opx@ file.
--
-- Every case but 'EmptyPattern' names a line, because both formats are line
-- oriented enough for that to be the useful thing to say — an @.opx@ is XML,
-- but it is XML one property to a line, and the line is where a person will
-- look.
data ImportError
  = -- | Nothing in the file was a crease. Either it is empty, or it is not a
    -- file of this format at all.
    EmptyPattern
  | -- | A line that is not the shape the format calls for. Carries the line
    -- and what was expected.
    MalformedLine Int Text
  | -- | A line type code the format does not define. Carries the line and the
    -- code.
    UnknownLineType Int Int
  | -- | A segment whose two endpoints are the same point, to within
    -- 'mergeTolerance'. It names no direction, so it is not a crease, and
    -- keeping it would put an edge from a vertex to itself into the frame.
    DegenerateSegment Int
  deriving stock (Eq, Show)

-- | A message suitable for printing to a terminal.
renderImportError :: ImportError -> Text
renderImportError = \case
  EmptyPattern -> "no creases in this file"
  MalformedLine n what -> atLine n <> what
  UnknownLineType n code -> atLine n <> "unknown line type " <> T.pack (show code)
  DegenerateSegment n -> atLine n <> "the two endpoints are the same point"
  where
    atLine n = "line " <> T.pack (show n) <> ": "

-- | How close two endpoints have to be before they are taken to be one vertex.
--
-- Exported so that a test can state the number rather than guess at it, and so
-- that the reason for it lives next to the value. See the module header for
-- why it is relative to the pattern rather than absolute.
--
-- Zero only when every endpoint in the file is the same point — or when there
-- are no segments at all — and then every segment is degenerate and
-- 'frameFromSegments' rejects the first of them before the tolerance is used
-- for anything else.
mergeTolerance :: [Segment] -> Double
mergeTolerance segments = case boxFromPoints (concatMap ends segments) of
  Nothing -> 0
  Just box -> 1e-9 * norm (boxSize box)
  where
    ends s = [segStart s, segEnd s]

-- | Build a frame from a list of segments, merging endpoints that coincide.
--
-- The vertices come out in the order the file first mentions them, so reading
-- a file twice gives the same numbering, and the numbering follows the file
-- rather than some sort we imposed on it.
--
-- Only the vertices are rebuilt. Two creases that /cross/ without either
-- naming the crossing point stay crossed, which makes the result a drawing
-- rather than a planar graph; splitting them, and building the faces that
-- follow, is a separate job that the file gives no help with.
frameFromSegments :: [Segment] -> Either ImportError Frame
frameFromSegments [] = Left EmptyPattern
frameFromSegments segments = do
  mapM_ nonDegenerate segments
  pure
    emptyFrame
      { frameClasses = ["creasePattern"],
        frameAttributes = ["2D"],
        verticesCoords = [[v2x p, v2y p] | p <- reverse (mergeSeen final)],
        edgesVertices = reverse edges,
        edgesAssignment = map segAssignment segments
      }
  where
    tolerance = mergeTolerance segments

    nonDegenerate s
      | norm (segEnd s ^-^ segStart s) <= tolerance = Left (DegenerateSegment (segLine s))
      | otherwise = Right ()

    (final, edges) = foldl' addEdge (emptyMerge, []) segments

    -- The bang is load-bearing on a large file: foldl' forces the pair it is
    -- accumulating to weak head normal form, which is the pair and not what is
    -- inside it, so without it every intern of every endpoint stays a thunk
    -- until the very end. See docs/notes/strict-fields.md.
    addEdge (!merge0, acc) s =
      let (a, merge1) = intern tolerance (segStart s) merge0
          (b, merge2) = intern tolerance (segEnd s) merge1
       in (merge2, (a, b) : acc)

-- | Build a whole document from a list of segments.
--
-- The metadata is only what reading the file established: it is one frame, it
-- is a crease pattern, and it is flat. Nothing claims a @file_creator@ or a
-- @frame_unit@, because neither format records one and inventing a value that
-- a later 'Senbazuru.Fold.Load.saveFoldFile' would write out is how a guess
-- becomes a fact.
foldFileFromSegments :: [Segment] -> Either ImportError FoldFile
foldFileFromSegments segments = do
  frame <- frameFromSegments segments
  pure
    FoldFile
      { fileSpec = Just 1.2,
        fileCreator = Nothing,
        fileAuthor = Nothing,
        fileTitle = Nothing,
        fileDescription = Nothing,
        fileClasses = ["singleModel"],
        keyFrame = frame,
        otherFrames = []
      }

-- | The vertices found so far, and a grid for finding them again.
--
-- 'mergeSeen' is in reverse order of discovery, which is the usual accumulator
-- trick: consing is cheap, and the list is reversed once at the end.
data Merge = Merge
  { mergeGrid :: !(Map (Int, Int) [(VertexId, V2)]),
    mergeSeen :: ![V2],
    mergeCount :: !Int
  }

emptyMerge :: Merge
emptyMerge = Merge {mergeGrid = M.empty, mergeSeen = [], mergeCount = 0}

-- | Find the vertex at a point, or make one.
--
-- Only the nine cells around the point are searched. That is enough: two
-- points within one tolerance of each other are at most one cell apart on each
-- axis, so anything close enough to merge with is in one of the nine.
--
-- Where two existing vertices are both within tolerance of the new point —
-- possible, since they may be up to two tolerances apart from each other — the
-- first one found wins. Which one that is depends on the order the file listed
-- them in, and a pattern where it matters was already ambiguous at this scale.
intern :: Double -> V2 -> Merge -> (VertexId, Merge)
intern tolerance p merge = case nearby of
  ((existing, _) : _) -> (existing, merge)
  [] ->
    ( fresh,
      merge
        { mergeGrid = M.insertWith (<>) (cellOf tolerance p) [(fresh, p)] (mergeGrid merge),
          mergeSeen = p : mergeSeen merge,
          mergeCount = mergeCount merge + 1
        }
    )
  where
    fresh = VertexId (mergeCount merge)
    (cx, cy) = cellOf tolerance p
    nearby =
      [ candidate
        | dx <- [-1, 0, 1],
          dy <- [-1, 0, 1],
          candidate@(_, q) <- M.findWithDefault [] (cx + dx, cy + dy) (mergeGrid merge),
          norm (q ^-^ p) <= tolerance
      ]

-- | Which cell of the tolerance-wide grid a point falls in.
cellOf :: Double -> V2 -> (Int, Int)
cellOf tolerance (V2 x y) = (floor (x / tolerance), floor (y / tolerance))
