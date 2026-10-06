-- |
-- Module      : Senbazuru.Sequence.Run
-- Description : Running a fold sequence: the state it threads from move to move, and where that state starts.
--
-- A run performs a checked sequence one move at a time. Between moves it
-- holds a /fold state/ (see docs/glossary.md, "Fold sequences"): the paper as
-- the next move will find it. A finished run hands back move records
-- ("Senbazuru.Sequence.Record") and never the state itself, so no reader of a
-- run can come to depend on how the runner keeps its paper. 'FoldState' is
-- opaque for the same reason.
--
-- So far this module holds the start: 'sheetState' turns a sheet, a file's key
-- frame, into the state a run begins from. The moves come next.
--
-- == What a fold state holds
--
-- The /working pattern/: the sheet's crease pattern, cut at every crossing,
-- with its vertices in material coordinates, where the paper lay on the flat
-- sheet. Folding never changes those coordinates; a move changes only the
-- crease angles and the layer orders written on the pattern, and the pattern
-- is folded afresh from them. Folded coordinates fed back as material would
-- fold the paper a second time.
--
-- And the /anchor/: the point of paper that stays still while the rest of the
-- paper moves, so that a model does not wander across the page from one
-- picture to the next. It is a material point, not a face id, because ids do
-- not survive the cutting a new crease makes.
--
-- == How a sheet becomes a starting state
--
-- * __The key frame only.__ A sheet is the paper before any folding. A key
--   frame with no vertices belongs to a file of folded states, and one that
--   leaves the plane, or calls itself a folded form, is folded already; both
--   are refused.
-- * __Flat.__ Every crease starts at angle 0, whatever angle the file wrote:
--   @examples\/blintz-base.fold@ records its four corners folded in, and a
--   blintz sequence must not start already folded. (Starting from the file's
--   angles is @start folded@, a later milestone.)
-- * __Intent kept.__ A crease keeps the letter it was drawn with, M or V,
--   though it now lies flat. That departs from "a valley at angle 0 is not a
--   valley", on purpose: the library turns only an M, V or U crease, and a
--   later move needs to know which way a crease was made. It is safe because
--   folding reads angles before letters, and a crease at 0 orders no layers.
--   An F crease the file drew at a nonzero angle contradicts itself, since F
--   means unfolded, so its angle is believed: M below 0, V above. A U crease
--   stays U whatever its angle, since U says only that the direction is
--   undecided, and the runner must not invent a direction nobody gave.
-- * __Clean.__ Layer orders and unknown keys are dropped, since nothing has
--   been stacked yet. Faces are cut at crossings and traced where the file
--   has none, and every face's ring runs anticlockwise on the sheet, so that a
--   face's normal points the way the file's +z does.
-- * __The anchor, by default.__ The vertex mean, the average of the corners,
--   of the largest face, ties to the lowest and then the leftmost vertex mean,
--   a tie being close enough that rounding could have made the difference.
--   That face is put first, because folding holds its first face still. A
--   vertex mean of a face that is not convex can lie outside it, and is
--   refused: the author names the anchor instead.
--
-- == The number that looks arbitrary
--
-- "Flat" for a crease's letter means within 'atRest', 1e-10 degrees, of 0:
-- the same threshold 'Senbazuru.Origami.Surface' uses to decide which creases
-- a bent surface keeps, so the two cannot disagree about a crease.
module Senbazuru.Sequence.Run
  ( -- * The state a run threads
    FoldState,
    workingPattern,
    stateAnchor,

    -- * Starting
    sheetState,
    squareSheet,
  )
where

import Control.Monad (when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Faces (sheetOf, tolerance)
import Senbazuru.Fold.Query (FrameKind (..), atRest, frameKind, frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (centroid, insideRing, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, zSpan)
import Senbazuru.Sequence.Error (FoldedBy (..), SheetProblem (..))
import Senbazuru.Sequence.Record (MaterialPoint (..))

-- | The paper between two moves of a run: the working pattern and the anchor.
-- Opaque; the header says what each is and why.
data FoldState = FoldState
  { theWorking :: !Frame,
    theAnchor :: !MaterialPoint
  }
  deriving stock (Eq, Show)

-- | The working pattern: the sheet's creases cut at every crossing, its
-- vertices in material coordinates, the anchor's face first.
workingPattern :: FoldState -> Frame
workingPattern = theWorking

-- | The anchor: the point of paper that stays still.
stateAnchor :: FoldState -> MaterialPoint
stateAnchor = theAnchor

-- | The state a run starts from, given the file the header's @sheet@ names:
-- its key frame laid flat, with its creases' letters kept, its faces traced
-- and wound anticlockwise, and the largest face's vertex mean as the anchor.
-- The header says why each.
sheetState :: FoldFile -> Either SheetProblem FoldState
sheetState file = do
  let key = keyFrame file
  points <- first SheetNotAPattern (frameVertices key)
  when (null points) (Left (SheetHasNoVertices (length (otherFrames file))))
  case frameKind (frameClasses key) points of
    FoldedForm -> Left (SheetAlreadyFolded (if hasRelief points then ByRelief (zSpan points) else ByClass))
    CreasePattern -> pure ()
  planar <- first SheetNotAPattern (withPlanarFaces key {faceOrders = [], frameExtras = mempty})
  material <- first SheetNotAPattern (IM.fromList . zip [0 ..] . map flat <$> frameVertices planar)
  room <- first SheetNotAPattern (tolerance <$> sheetOf planar)
  let ring face = [p | VertexId i <- face, Just p <- [IM.lookup i material]]
      faces = [if signedArea (ring face) < 0 then reverse face else face | face <- facesVertices planar]
      measured = [(i, face, abs (signedArea (ring face)), centroid (ring face)) | (i, face) <- zip [0 :: Int ..] faces]
  (index, anchorFace, anchor) <- case defaultAnchor room measured of
    Just (i, face, _, mean)
      | insideRing room (ring face) mean -> Right (i, face, mean)
      | otherwise -> Left (DefaultAnchorOutside mean)
    Nothing -> Left SheetHasNoFaces
  let angles = edgesFoldAngle planar
      letters = zipWith intent (edgesAssignment planar) (angles ++ repeat 0)
  pure
    FoldState
      { theWorking =
          planar
            { edgesAssignment = letters,
              edgesFoldAngle = map (const 0) letters,
              facesVertices = anchorFace : [face | (j, face) <- zip [0 ..] faces, j /= index]
            },
        theAnchor = MaterialPoint anchor
      }
  where
    flat (V3 x y _) = V2 x y
    -- An F crease at an angle has its angle believed; every other letter is
    -- kept as drawn, U included.
    intent letter angle = case letter of
      Flat
        | angle < negate atRest -> Mountain
        | angle > atRest -> Valley
      _ -> letter

-- | The face whose vertex mean is the default anchor, numbered, with its area
-- and vertex mean: the largest face, and among faces of one area the lowest
-- vertex mean and then the leftmost. A tie is a billionth of the largest area,
-- or the sheet's own tolerance in a height or a distance across, so that a
-- rounding error in an area or a mean cannot decide one. 'Nothing' for a
-- sheet with no faces.
defaultAnchor :: Double -> [(Int, [VertexId], Double, V2)] -> Maybe (Int, [VertexId], Double, V2)
defaultAnchor room measured = case measured of
  [] -> Nothing
  _ ->
    let biggest = maximum [area | (_, _, area, _) <- measured]
        largest = [m | m@(_, _, area, _) <- measured, area >= biggest - 1e-9 * biggest]
        lowest = minimum [y | (_, _, _, V2 _ y) <- largest]
        low = [m | m@(_, _, _, V2 _ y) <- largest, y <= lowest + room]
        leftmost = minimum [x | (_, _, _, V2 x _) <- low]
     in find (\(_, _, _, V2 x _) -> x <= leftmost + room) low

-- | The sheet @sheet square@ names: the unit square, its four corners
-- anticlockwise from the origin, four border edges and one face.
squareSheet :: FoldFile
squareSheet =
  FoldFile
    { fileSpec = Just 1.2,
      fileCreator = Nothing,
      fileAuthor = Nothing,
      fileTitle = Nothing,
      fileDescription = Nothing,
      fileClasses = [],
      keyFrame =
        emptyFrame
          { frameClasses = ["creasePattern"],
            verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
            edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0)]],
            edgesAssignment = replicate 4 Border,
            facesVertices = [map VertexId [0, 1, 2, 3]]
          },
      otherFrames = []
    }
