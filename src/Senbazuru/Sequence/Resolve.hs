-- |
-- Module      : Senbazuru.Sequence.Resolve
-- Description : Naming paper on a flat state: points, fold lines, and the creases a fold turns about.
--
-- A fold sequence never names paper by an id. It says @corner south-east@,
-- @centre@ or @(1\/4, 3\/4)@, and this module finds the paper those words
-- mean in the state a run has reached (see docs/glossary.md, "Fold
-- sequences", and @PRDs\/02-language-semantics.md@, §4).
--
-- == Two places a point can be
--
-- Every point is named where it lay on the flat sheet, in /sheet lengths/: the
-- sheet's bounding box has its south-west corner at (0, 0) and its longer side
-- 1, whatever units the file uses. 'materialPoint' answers in material
-- coordinates, the file's own, and the answer never changes as the paper
-- folds: the midpoint of two corners is the same paper after those corners
-- are folded onto one spot.
--
-- A fold line is different. @corner south-east to centre@ means the fold that
-- lays that corner where the centre is /now/, so 'foldLine' works where the
-- paper lies after the moves so far, and 'positionOf' gives a point's place
-- there: its material point carried by the face it lies on. On the first move
-- the two places coincide, which hides the difference; by the second they do
-- not. Computing a fold line on the flat sheet is the mistake to avoid.
--
-- == The slot decides, not the spelling
--
-- What a point must be depends on the slot it fills.
--
-- * __A position__, such as either point of @P to Q@, must lie on paper, and
--   every face sharing it must fold it to one place. A typed @(u, v)@ near a
--   vertex but not on it is refused as a /near miss/: the author almost
--   certainly meant the vertex and wrote a rounded number, and a separate
--   point there would leave a sliver of crease. A typed point within the
--   sheet's tolerance of a vertex is that vertex, exactly.
-- * __A region__, such as the anchor, must lie strictly inside one face: a
--   point on a crease belongs to two.
--
-- == The hinge is creases the paper already has
--
-- 'hingeAlong' finds the creases lying along a fold line. So far a run folds
-- only along creases the paper has: a line that crosses a face where no crease
-- runs would need a new crease, and creasing is a later change, so it is
-- refused as not run yet rather than folded wrong.
--
-- == Only flat states
--
-- Every construction here needs the paper lying flat, every face in one
-- plane, which is what a book's flat diagrams show. 'flatState' refuses any
-- other.
module Senbazuru.Sequence.Resolve
  ( -- * The state named against
    FlatState,
    flatState,

    -- * Points
    materialPoint,
    positionOf,
    toSheetLengths,

    -- * Fold lines and hinges
    FoldLine (..),
    foldLine,
    hingeAlong,

    -- * Regions
    regionFace,
  )
where

import Control.Monad (unless, when)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IM
import Data.IntSet (IntSet)
import Data.IntSet qualified as IS
import Data.List (minimumBy)
import Data.Ord (comparing)
import Senbazuru.Fold.Faces (toleranceOf)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..), boxCentre, boxFromPoints, boxSize, perpendicular)
import Senbazuru.Geometry.Polygon (cross2, distanceToSegment, edges, insideRing)
import Senbazuru.Geometry.Rigid (Rigid, applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, zSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..))
import Senbazuru.Sequence.Error (ResolveProblem (..))
import Senbazuru.Sequence.Syntax (Compass (..), Corner (..), Line (..), Name (..), Point (..))

-- | A flat state, measured once for naming paper on it: where each vertex was
-- on the sheet and where it is now, how each face is placed, which creases
-- there are, and the sheet's box and tolerance.
data FlatState = FlatState
  { flatMaterial :: !(IntMap V2),
    flatPlaced :: !(IntMap V2),
    flatPlacements :: !(IntMap Rigid),
    flatFaces :: ![(FaceId, [Int])],
    flatEdges :: ![(EdgeId, Int, Int, Assignment)],
    flatBoundary :: !IntSet,
    flatBox :: !Box,
    flatRoom :: !Double
  }

-- | A fold, measured for naming paper on it. Refused unless every face lies
-- in one plane.
flatState :: Folded -> Either ResolveProblem FlatState
flatState folded = do
  let paper = foldedPattern folded
      material = IM.fromList [(i, V2 x y) | (i, x : y : _) <- zip [0 ..] (verticesCoords paper)]
      placed3 = [V3 x y (case rest of z : _ -> z; [] -> 0) | x : y : rest <- verticesCoords (foldedFrame folded)]
  when (hasRelief placed3) (Left (ConstructionInTheAir (zSpan placed3)))
  box <- maybe (Left (NotRunYet "naming paper on a state with no vertices")) Right (boxFromPoints (IM.elems material))
  let letters = case edgesAssignment paper of
        [] -> repeat Unassigned
        given -> given
      sides = [(EdgeId e, a, b, letter) | (e, (VertexId a, VertexId b), letter) <- zip3 [0 ..] (edgesVertices paper) letters]
  pure
    FlatState
      { flatMaterial = material,
        flatPlaced = IM.fromList [(i, V2 x y) | (i, V3 x y _) <- zip [0 ..] placed3],
        flatPlacements = foldedPlacements folded,
        flatFaces = [(FaceId f, [v | VertexId v <- ring]) | (f, ring) <- zip [0 ..] (facesVertices paper)],
        flatEdges = sides,
        flatBoundary = IS.fromList [v | (_, a, b, Border) <- sides, v <- [a, b]],
        flatBox = box,
        flatRoom = toleranceOf (IM.elems material)
      }

-- | The sheet's longer side, in material units: one sheet length.
sheetLength :: FlatState -> Double
sheetLength st = let V2 w h = boxSize (flatBox st) in max w h

-- | A material point in sheet lengths, the author's units.
toSheetLengths :: FlatState -> V2 -> V2
toSheetLengths st p = (1 / sheetLength st) *^ (p ^-^ boxMin (flatBox st))

-- | Where the point lay on the flat sheet, in material coordinates. Every form
-- but @meet@ is worked out here, on the sheet; @meet@ needs positions, and is
-- not run yet.
materialPoint :: FlatState -> Point -> Either ResolveProblem V2
materialPoint st = \case
  CornerOf corner -> cornerOf corner
  Centre -> Right (boxCentre box)
  AtSheet u v -> Right (boxMin box ^+^ (sheetLength st *^ V2 (fromRational u) (fromRational v)))
  MidpointOf p q -> along 0.5 p q
  FractionAlong r p q -> along (fromRational r) p q
  MidpointOfEdge side -> Right (edgeMidpoint side)
  Meet {} -> Left (NotRunYet "\"meet L1 L2\", which is measured where the paper is now,")
  EndOfCreaseOf {} -> Left (NotRunYet "\"end of crease of NAME nearest P\"")
  PointNamed (Name name) -> Left (NotRunYet ("the mark " <> name))
  where
    box = flatBox st
    Box (V2 x0 y0) (V2 x1 y1) = box
    along r p q = do
      a <- materialPoint st p
      b <- materialPoint st q
      pure (a ^+^ (r *^ (b ^-^ a)))
    -- A compass corner names a corner of the sheet's box, and only where the
    -- sheet's outline has a corner there: a boundary vertex within the
    -- tolerance, taken exactly.
    cornerOf corner =
      let target = case corner of
            SouthWest -> V2 x0 y0
            SouthEast -> V2 x1 y0
            NorthEast -> V2 x1 y1
            NorthWest -> V2 x0 y1
          near = [(norm (p ^-^ target), p) | v <- IS.toList (flatBoundary st), Just p <- [IM.lookup v (flatMaterial st)], norm (p ^-^ target) <= flatRoom st]
       in case near of
            [] -> Left (NoCornerThere corner)
            _ -> Right (snd (minimumBy (comparing fst) near))
    edgeMidpoint = \case
      North -> V2 (0.5 * (x0 + x1)) y1
      South -> V2 (0.5 * (x0 + x1)) y0
      East -> V2 x1 (0.5 * (y0 + y1))
      West -> V2 x0 (0.5 * (y0 + y1))

-- | Where the point is now: the position slot. The point must lie on paper,
-- and every face whose outline holds it must fold it to one place. A typed
-- @(u, v)@ near a vertex, within @band@ sheet lengths and not within the
-- sheet's tolerance, is a near miss; within the tolerance it is the vertex.
positionOf :: Double -> FlatState -> Point -> Either ResolveProblem V2
positionOf band st point = do
  m <- materialPoint st point
  m' <- case point of
    AtSheet u v -> literal (u, v) m
    _ -> Right m
  placedAt st m'
  where
    literal written m = case [(norm (p ^-^ m), i, p) | (i, p) <- IM.toList (flatMaterial st)] of
      [] -> Right m
      vertices ->
        let (distance, i, p) = minimumBy (comparing (\(d, _, _) -> d)) vertices
            inSheetLengths = distance / sheetLength st
         in if distance <= flatRoom st
              then Right p
              else
                if inSheetLengths <= band
                  then Left (NearMiss written i (toSheetLengths st p) inSheetLengths)
                  else Right m

-- | A material point's place in the fold, through every face whose outline
-- holds it.
placedAt :: FlatState -> V2 -> Either ResolveProblem V2
placedAt st m = case [flat (applyRigid placement (V3 x y 0)) | (FaceId f, ring) <- flatFaces st, holds (ringOf st ring), Just placement <- [IM.lookup f (flatPlacements st)]] of
  [] -> Left (OffThePaper (toSheetLengths st m))
  placements@(first' : _) ->
    let spread = maximum [norm (p ^-^ q) | p <- placements, q <- placements]
     in if spread <= flatRoom st then Right first' else Left (PlacementsDisagree (toSheetLengths st m) (spread / sheetLength st))
  where
    V2 x y = m
    flat (V3 a b _) = V2 a b
    holds ring = holdsPoint st ring m

-- | Whether a face's outline holds the point, edges and corners included,
-- within the sheet's tolerance.
holdsPoint :: FlatState -> [V2] -> V2 -> Bool
holdsPoint st ring m = insideRing 0 ring m || any ((<= flatRoom st) . (`distanceToSegment` m)) (edges ring)

-- | A fold line where the paper now lies: a point on it and its direction, of
-- length 1.
data FoldLine = FoldLine {linePoint :: !V2, lineDirection :: !V2}
  deriving stock (Eq, Show)

-- | The fold line the reference names, where the paper now lies. So far the
-- two forms the blintz needs and the one beside them: @[P, Q]@, through two
-- points, and @P to Q@, laying P onto Q, whose line is the perpendicular
-- bisector of where P and Q now are.
foldLine :: Double -> FlatState -> Line -> Either ResolveProblem FoldLine
foldLine band st = \case
  Segment p q -> do
    (a, b) <- two p q
    pure (FoldLine a (unit (b ^-^ a)))
  Onto p q -> do
    (a, b) <- two p q
    pure (FoldLine (0.5 *^ (a ^+^ b)) (perpendicular (unit (b ^-^ a))))
  EdgeOf _ -> notYet "\"edge S\" as a fold line"
  LineOnto {} -> notYet "\"L1 to L2\""
  PerpendicularThrough {} -> notYet "\"perpendicular to L through P\""
  PointToLineThrough {} -> notYet "\"P to L through Q\""
  TwoToTwo {} -> notYet "\"P to L1 and Q to L2\""
  PointToLinePerpendicular {} -> notYet "\"P to L1 perpendicular to L2\""
  PointToLine {} -> notYet "\"P to L\""
  ExistingCrease {} -> notYet "\"crease [P, Q]\""
  HingeOf _ -> notYet "\"hinge of NAME\""
  CreaseOf _ -> notYet "\"crease of NAME\""
  ModelSegment {} -> notYet "\"model [...]\""
  LineNamed (Name name) -> notYet ("the line " <> name)
  where
    notYet = Left . NotRunYet
    two p q = do
      a <- positionOf band st p
      b <- positionOf band st q
      if norm (b ^-^ a) <= flatRoom st then Left DegenerateConstruction else Right (a, b)
    unit v = (1 / norm v) *^ v

-- | The creases lying along the fold line: the candidates a fold turns
-- about. Refused if the line runs along no crease, and, until creasing is
-- run, if it crosses a face where no crease runs.
--
-- Every crease along the line is a candidate, on every layer and whatever its
-- letter. A fold turns only those beside the paper it moves, and an F crease
-- cannot hinge at all, so the runner keeps the creases beside its moving
-- flap, and refuses an F among them, when it chooses that flap.
--
-- A face counts as crossed when it has corners strictly on both sides of the
-- line. On a face that is not convex, a line can pass through the notch
-- between two arms with corners on both sides and miss the paper; that is
-- refused too, which costs a fold that would have been possible and never
-- folds one that is not.
hingeAlong :: FlatState -> FoldLine -> Either ResolveProblem [EdgeId]
hingeAlong st (FoldLine origin direction) = do
  let side v = maybe 0 (\p -> cross2 direction (p ^-^ origin)) (IM.lookup v (flatPlaced st))
      room = flatRoom st
      crossed = [f | (f, ring) <- flatFaces st, any ((> room) . side) ring, any ((< negate room) . side) ring]
  unless (null crossed) (Left (NotRunYet "a fold whose line crosses paper where no crease runs, which needs a new crease,"))
  case [e | (e, a, b, letter) <- flatEdges st, letter `notElem` [Border, Cut, Join], abs (side a) <= room, abs (side b) <= room] of
    [] -> Left NoSolution
    hinge -> Right hinge

-- | The face a material point lies strictly inside: the region slot, such as
-- the anchor's. A point on a crease or a corner lies in no one face.
regionFace :: FlatState -> V2 -> Either ResolveProblem FaceId
regionFace st m = case [f | (f, ring) <- flatFaces st, insideRing (flatRoom st) (ringOf st ring) m] of
  [f] -> Right f
  faces
    | any (\(_, ring) -> holdsPoint st (ringOf st ring) m) (flatFaces st) -> Left (NotInOneFace (toSheetLengths st m) (length faces))
    | otherwise -> Left (OffThePaper (toSheetLengths st m))

-- | A face's corners on the sheet.
ringOf :: FlatState -> [Int] -> [V2]
ringOf st ring = [p | v <- ring, Just p <- [IM.lookup v (flatMaterial st)]]
