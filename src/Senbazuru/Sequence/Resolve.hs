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
-- == The hinge is creases the paper has
--
-- 'hingeAlong' finds the creases lying along a fold line, and refuses a line
-- that crosses a face where no crease runs. A runner creases such paper
-- first: 'crossedFaces' says where the line crosses it, and 'chordsAcross'
-- where on the sheet the new creases go.
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
    lineAlong,
    hingeAlong,
    crossedFaces,
    chordsAcross,
    firstLineSeed,
    straddles,
    eastOrNorth,
    lineAsSeen,

    -- * Regions
    regionFace,

    -- * The paper a fold turns
    seedFaces,
    Selection (..),
    flapOf,
    hingeStretches,
  )
where

import Control.Monad (unless, when)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IM
import Data.IntSet (IntSet)
import Data.IntSet qualified as IS
import Data.List (minimumBy, nub, sortOn)
import Data.Map.Strict qualified as M
import Data.Ord (comparing)
import Senbazuru.Fold.Faces (toleranceOf)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..), boxCentre, boxFromPoints, boxSize, perpendicular)
import Senbazuru.Geometry.Polygon (centroid, cross2, distanceToSegment, edges, insideRing)
import Senbazuru.Geometry.Rigid (Rigid, applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, zSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..))
import Senbazuru.Sequence.Error (CandidateLine (..), ResolveProblem (..), SelectionError (..), TakenBecause (..))
import Senbazuru.Sequence.Record (MaterialPoint (..), MaterialSegment (..))
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

-- | A direction of length 1.
unit :: V2 -> V2
unit v = (1 / norm v) *^ v

-- | The fold line the reference names, where the paper now lies:
--
-- * @[P, Q]@, through two points;
-- * @P to Q@, laying P onto Q, whose line is the perpendicular bisector of
--   where P and Q now are;
-- * @edge S@, the line the sheet's side S lies along now, if it lies along
--   one;
-- * @L1 to L2@, laying one line onto another, where L1 and L2 are each an
--   edge or @[P, Q]@ ('lineOnto').
foldLine :: Double -> FlatState -> Line -> Either ResolveProblem FoldLine
foldLine band st = \case
  Segment p q -> do
    (a, b) <- two p q
    pure (FoldLine a (unit (b ^-^ a)))
  Onto p q -> do
    (a, b) <- two p q
    pure (FoldLine (0.5 *^ (a ^+^ b)) (perpendicular (unit (b ^-^ a))))
  EdgeOf side -> do
    (a, b) <- edgeNow st side
    pure (FoldLine a (unit (b ^-^ a)))
  LineOnto l1 l2 nearest -> do
    s1 <- operand l1
    s2 <- operand l2
    lineOnto band st s1 s2 nearest
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
    -- A line that L1 to L2 lays onto another needs a stretch, not just a
    -- direction: which way round it maps decides between two answers.
    operand = \case
      EdgeOf side -> edgeNow st side
      Segment p q -> two p q
      _ -> notYet "\"L1 to L2\" between lines other than an edge and [P, Q]"

-- | The pieces of the sheet's outline along side S, as the working pattern
-- numbers its edges, each with its ends: every edge with both ends on that
-- side of the sheet's box.
edgePieces :: FlatState -> Compass -> [(EdgeId, Int, Int)]
edgePieces st side = [(e, a, b) | (e, a, b, _) <- flatEdges st, onSide a, onSide b]
  where
    Box (V2 x0 y0) (V2 x1 y1) = flatBox st
    onSide v = case IM.lookup v (flatMaterial st) of
      Just (V2 x y) -> abs (along x y) <= flatRoom st
      Nothing -> False
    along x y = case side of
      North -> y - y1
      South -> y - y0
      East -> x - x1
      West -> x - x0

-- | Side S of the sheet where it lies now, from one end to the other: its
-- pieces must lie on one line, within the sheet's tolerance. On a fold that
-- has turned part of the side away, they do not, and the side names no line.
edgeNow :: FlatState -> Compass -> Either ResolveProblem (V2, V2)
edgeNow st side = case [(p, q) | (_, a, b) <- edgePieces st side, Just p <- [IM.lookup a (flatPlaced st)], Just q <- [IM.lookup b (flatPlaced st)]] of
  [] -> Left (EdgeNotStraight side [])
  pieces -> do
    let (p, q) = minimumBy (comparing (\(a, b) -> negate (norm (b ^-^ a)))) pieces
        direction = unit (q ^-^ p)
        ends = concat [[a, b] | (a, b) <- pieces]
        off x = abs (cross2 direction (x ^-^ p))
        at x = dot direction (x ^-^ p)
    unless (all ((<= flatRoom st) . off) ends) (Left (EdgeNotStraight side [(toSheetLengths st a, toSheetLengths st b) | (a, b) <- pieces]))
    pure (p ^+^ (minimum (map at ends) *^ direction), p ^+^ (maximum (map at ends) *^ direction))

-- | @L1 to L2@: the fold that lays one stretch of line onto another, the
-- third Huzita–Hatori construction (docs/notes/huzita-hatori.md). Lines that
-- are parallel have one answer, the line midway between them. Lines that
-- cross have two, the lines halving the angles where they cross, at right
-- angles to each other.
--
-- Of the answers, one that crosses no paper is never taken. If more than one
-- is left, the one that lays the first stretch onto the second, rather than
-- onto the line beyond it, is preferred; only if that leaves no single answer
-- does the author have to say @nearest P@.
--
-- A @nearest P@ the rules did not need is still read, and has to agree with
-- them: a P lying nearer another answer than the one taken is refused, not
-- ignored (owner decision 41). Any answer counts as another, one crossing no
-- paper included, since an author pointing at it expected it. A P as near to
-- both, such as the point where the two answers cross, points at neither,
-- and does not disagree. Being read, P has to name a place on the paper
-- whether or not it is needed: @nearest (2, 2)@ is refused as off the paper
-- even where one answer is all there is.
--
-- With both stretches lying on the paper, which is one piece, some answer
-- always crosses it. Two parallel stretches lie either side of their
-- midline. Two crossing lines' halving lines cut the plane into four
-- quarters, each holding one ray of one line, so one halving line has paper
-- on each side: a stretch on either side, or one running through the
-- crossing.
lineOnto :: Double -> FlatState -> (V2, V2) -> (V2, V2) -> Maybe Point -> Either ResolveProblem FoldLine
lineOnto band st (a1, b1) (a2, b2) nearest = do
  let room = flatRoom st
      d1 = unit (b1 ^-^ a1)
      d2 = unit (b2 ^-^ a2)
      apart = cross2 d1 (a2 ^-^ a1)
  answers <-
    if abs (cross2 d1 d2) * sheetLength st <= room
      then
        if abs apart <= room
          then Left DegenerateConstruction
          else Right [FoldLine (a1 ^+^ ((0.5 * apart) *^ perpendicular d1)) d1]
      else
        let crossing = a1 ^+^ ((cross2 (a2 ^-^ a1) d2 / cross2 d1 d2) *^ d1)
         in Right [FoldLine crossing (unit (d1 ^+^ d2)), FoldLine crossing (unit (d1 ^-^ d2))]
  near <- traverse (positionOf band st) nearest
  let onPaper = filter (crossesPaper st) answers
      preferred = filter laysOnto onPaper
      laysOnto line =
        let image = map (reflectIn line) [a1, b1]
            at x = dot d2 (x ^-^ a2)
         in min (norm (b2 ^-^ a2)) (maximum (map at image)) - max 0 (minimum (map at image)) > room
      listed = map (candidateOf st) answers
      distanceFrom p (FoldLine o d) = abs (cross2 d (p ^-^ o))
      -- The answer the rules took, held to a nearest P they did not need.
      agreeing because taken = case near of
        Nothing -> Right taken
        Just p ->
          let from = distanceFrom p
           in case sortOn fst [(from line, line) | line <- answers, from line + room < from taken] of
                (_, pointed) : _ -> Left (NearestDisagrees (toSheetLengths st p) (candidateOf st taken) because (candidateOf st pointed))
                [] -> Right taken
  case (onPaper, preferred) of
    ([], _) -> Left NoSolution
    ([only], _) -> agreeing OnlyOnPaper only
    (_, [only]) -> agreeing LaysStretchOntoStretch only
    (several, _) -> case near of
      Nothing -> Left (NeedsNearest listed)
      Just p -> do
        let pool = if null preferred then several else preferred
        case sortOn fst [(distanceFrom p line, line) | line <- pool] of
          (d, line) : rest | all ((> d + room) . fst) rest -> Right line
          _ -> Left (NearestAmbiguous (toSheetLengths st p) listed)

-- | Whether a line crosses the paper: has paper strictly on both sides. The
-- paper is one piece, so paper on both sides means the line passes through
-- it somewhere.
crossesPaper :: FlatState -> FoldLine -> Bool
crossesPaper st (FoldLine origin direction) =
  let sides = [cross2 direction (p ^-^ origin) | p <- IM.elems (flatPlaced st)]
   in any (> flatRoom st) sides && any (< negate (flatRoom st)) sides

-- | A point's mirror image in a line.
reflectIn :: FoldLine -> V2 -> V2
reflectIn (FoldLine origin direction) p =
  let offset = p ^-^ origin
   in origin ^+^ ((2 * dot offset direction) *^ direction) ^-^ offset

-- | An answer as an author can read it: in sheet lengths, through the point
-- of the line nearest the middle of the paper, and pointing east or north.
candidateOf :: FlatState -> FoldLine -> CandidateLine
candidateOf st line = let (through, along) = lineAsSeen st line in CandidateLine through along (crossesPaper st line)

-- | A line as a person is shown it, the same however it was found: in sheet
-- lengths, through its point nearest the middle of the paper, and pointing
-- east, or north for a line running north-south.
lineAsSeen :: FlatState -> FoldLine -> (V2, V2)
lineAsSeen st (FoldLine origin direction) =
  let middle = maybe origin boxCentre (boxFromPoints (IM.elems (flatPlaced st)))
   in (toSheetLengths st (origin ^+^ (dot (middle ^-^ origin) direction *^ direction)), eastOrNorth direction)

-- | A line's direction turned to point east, or north for a line running
-- north-south, so that one line always reads one way. A line within a hair of
-- north-south points north, whatever the sign of the rounding in its
-- east-west part.
eastOrNorth :: V2 -> V2
eastOrNorth direction@(V2 dx dy) =
  let southOrWest = if abs dx <= 1e-12 then dy < 0 else dx < 0
   in if southOrWest then (-1) *^ direction else direction

-- | The seed of @L1 to L2@ with no @moving@ point, and L1's stretch where it
-- lies now. The moving side is the one holding L1, and a run keeps a seed it
-- can name again in a region slot, which a point on L1 is not: so the seed
-- is the vertex mean of the face beside L1's longest piece, ties going to the
-- lowest piece, then the leftmost (PRDs\/02-language-semantics.md, §6.3). So
-- far L1 has pieces only when it is an edge of the sheet.
--
-- A tie is within the sheet's tolerance, in a length, a height or a distance
-- across, so that rounding cannot decide one: the rule 'Run.defaultAnchor'
-- follows for the anchor.
firstLineSeed :: FlatState -> Line -> Either ResolveProblem (V2, (V2, V2))
firstLineSeed st = \case
  EdgeOf side -> do
    stretch <- edgeNow st side
    let room = flatRoom st
        pieces = [(a, b, norm (q ^-^ p), 0.5 *^ (p ^+^ q)) | (_, a, b) <- edgePieces st side, Just p <- [IM.lookup a (flatMaterial st)], Just q <- [IM.lookup b (flatMaterial st)]]
        chosen = case pieces of
          [] -> []
          _ ->
            let longest = maximum [l | (_, _, l, _) <- pieces]
                long = [piece | piece@(_, _, l, _) <- pieces, l >= longest - room]
                lowest = minimum [y | (_, _, _, V2 _ y) <- long]
                low = [piece | piece@(_, _, _, V2 _ y) <- long, y <= lowest + room]
                leftmost = minimum [x | (_, _, _, V2 x _) <- low]
             in [(a, b) | (a, b, _, V2 x _) <- low, x <= leftmost + room]
    case chosen of
      (a, b) : _
        | ring : _ <- [ring | (_, ring) <- flatFaces st, (x, y) <- zip ring (drop 1 ring ++ take 1 ring), (x, y) `elem` [(a, b), (b, a)]] ->
            Right (centroid (ringOf st ring), stretch)
      _ -> Left (EdgeNotStraight side [])
  _ -> Left (NotRunYet "which side of \"L1 to L2\" moves, when L1 is not an edge of the sheet, without moving P,")

-- | Whether a stretch lies on both sides of a fold line, beyond the sheet's
-- tolerance.
straddles :: FlatState -> FoldLine -> (V2, V2) -> Bool
straddles st (FoldLine origin direction) (a, b) =
  let side p = cross2 direction (p ^-^ origin)
   in (side a > flatRoom st && side b < negate (flatRoom st)) || (side a < negate (flatRoom st) && side b > flatRoom st)

-- | The fold line along an edge, where the paper now lies: how @hinge of
-- NAME@ names a line, by a crease the named move turned about.
lineAlong :: FlatState -> EdgeId -> Either ResolveProblem FoldLine
lineAlong st edge = case [(a, b) | (e, a, b, _) <- flatEdges st, e == edge] of
  (a, b) : _
    | Just p <- IM.lookup a (flatPlaced st),
      Just q <- IM.lookup b (flatPlaced st) ->
        if norm (q ^-^ p) <= flatRoom st then Left DegenerateConstruction else Right (FoldLine p ((1 / norm (q ^-^ p)) *^ (q ^-^ p)))
  _ -> Left NoSolution

-- | The creases lying along the fold line: the candidates a fold turns
-- about. Refused if the line runs along no crease, or if it crosses a face
-- where no crease runs: a runner creases those first ('chordsAcross').
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
hingeAlong st line@(FoldLine origin direction) = do
  let side v = maybe 0 (\p -> cross2 direction (p ^-^ origin)) (IM.lookup v (flatPlaced st))
      room = flatRoom st
  unless (null (crossedFaces st line)) (Left (NotRunYet "a fold whose line crosses paper where no crease runs, which needs a new crease,"))
  case [e | (e, a, b, letter) <- flatEdges st, letter `notElem` [Border, Cut, Join], abs (side a) <= room, abs (side b) <= room] of
    [] -> Left NoSolution
    hinge -> Right hinge

-- | The faces a line crosses: those with corners strictly on both sides of
-- it. Where a fold line crosses one, no crease runs, and the paper has to be
-- creased before it can turn.
crossedFaces :: FlatState -> FoldLine -> [FaceId]
crossedFaces st (FoldLine origin direction) =
  let side v = maybe 0 (\p -> cross2 direction (p ^-^ origin)) (IM.lookup v (flatPlaced st))
      room = flatRoom st
   in [f | (f, ring) <- flatFaces st, any ((> room) . side) ring, any ((< negate room) . side) ring]

-- | Where a line crosses each of these faces, as stretches on the sheet: the
-- creases a fold along it needs and the paper does not have. Stretches that
-- meet end to end, across the edge between two faces, are one crease, so the
-- answer is the line's uncreased runs, in order along it.
--
-- The line is found where the paper lies, and its stretch across a face is
-- carried to the sheet without inverting the face's placement. A placement
-- is a rigid motion, and a rigid motion keeps the fraction of the way along
-- every segment: where the line cuts a face's edge a fraction t of the way
-- from one corner to the next, it cuts the edge's material segment the same
-- fraction along. A corner the line passes through is its own point on the
-- sheet.
--
-- A face that is not convex can hold the line more than once, so the points
-- where it meets the face's outline are taken in order along the line, and
-- each stretch between two of them is kept only if its middle lies inside the
-- face. A stretch along the outline is not inside it, and is not a crease to
-- make: it is one the face already has.
chordsAcross :: FlatState -> FoldLine -> [FaceId] -> [(V2, V2)]
chordsAcross st (FoldLine origin direction) faces =
  joined (sortOn (\(t, _, _) -> t) (concat [chords ring | (f, ring) <- flatFaces st, f `elem` faces]))
  where
    room = flatRoom st
    side p = cross2 direction (p ^-^ origin)
    along p = dot direction (p ^-^ origin)
    placed v = IM.lookup v (flatPlaced st)
    material v = IM.lookup v (flatMaterial st)
    -- Each stretch across a face: where it starts along the line, and its two
    -- ends on the sheet, in the line's direction.
    chords ring =
      let corners = [(p, m) | v <- ring, Just p <- [placed v], Just m <- [material v]]
          onLine = [(along p, p, m) | (p, m) <- corners, abs (side p) <= room]
          through =
            [ (along x, x, m ^+^ (t *^ (n ^-^ m)))
              | ((p, m), (q, n)) <- zip corners (drop 1 corners ++ take 1 corners),
                (side p > room && side q < negate room) || (side p < negate room && side q > room),
                let t = side p / (side p - side q)
                    x = p ^+^ (t *^ (q ^-^ p))
            ]
          meets = distinct (sortOn (\(a, _, _) -> a) (onLine ++ through))
          outline = map fst corners
       in [ (ta, m, n)
            | ((ta, x, m), (_, y, n)) <- zip meets (drop 1 meets),
              insideRing room outline (0.5 *^ (x ^+^ y))
          ]
    -- Two meetings closer than the tolerance along the line are one: the line
    -- through a corner meets it once and not again on either edge there.
    distinct = \case
      a@(ta, _, _) : b@(tb, _, _) : rest
        | tb - ta <= room -> distinct (a : rest)
        | otherwise -> a : distinct (b : rest)
      short -> short
    -- A stretch that starts where the last one ended continues it.
    joined = \case
      (ta, a, b) : (_, c, d) : rest
        | norm (c ^-^ b) <= room -> joined ((ta, a, d) : rest)
      (_, a, b) : rest -> (a, b) : joined rest
      [] -> []

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

-- | The faces a fold's seed picks: the one face it lies strictly inside, or,
-- for a seed at a corner where faces meet, every face there. A corner of the
-- sheet is a vertex, and a fold such as @corner south-east to centre@ names
-- its moving paper by one.
seedFaces :: FlatState -> V2 -> Either ResolveProblem [FaceId]
seedFaces st m = case [f | (f, ring) <- flatFaces st, insideRing room (ringOf st ring) m] of
  [f] -> Right [f]
  inside
    | any ((<= room) . norm . (^-^ m)) (IM.elems (flatMaterial st)) -> Right holding
    | null holding -> Left (OffThePaper (toSheetLengths st m))
    | otherwise -> Left (NotInOneFace (toSheetLengths st m) (length inside))
  where
    room = flatRoom st
    holding = [f | (f, ring) <- flatFaces st, holdsPoint st (ringOf st ring) m]

-- | The paper a fold turns, as "Senbazuru.Origami.Flap" takes it: the faces
-- that move, the creases of the hinge, and a moving face beside the first of
-- them, which the library measures the turn against.
data Selection = Selection
  { selectionMoving :: ![FaceId],
    selectionHinge :: ![EdgeId],
    selectionSide :: !FaceId
  }
  deriving stock (Eq, Show)

-- | The flap containing the seed: the faces still joined to the seed's faces
-- once every candidate crease along the line is cut. The hinge is the
-- candidates that border it, which leaves alone the creases of layers the
-- fold does not move. Refused if the seed lies on the line, if a corner seed
-- picks paper on both sides, if no candidate borders the flap, or if one that
-- does is F.
flapOf :: FlatState -> FoldLine -> [EdgeId] -> V2 -> [FaceId] -> Either SelectionError Selection
flapOf st (FoldLine origin direction) candidates seed picked = do
  let room = flatRoom st
      side p = cross2 direction (p ^-^ origin)
  case placedAt st seed of
    Right at | abs (side at) <= room -> Left (SeedOnTheLine (toSheetLengths st seed))
    _ -> Right ()
  let owners = M.fromListWith (++) [(key a b, [f]) | (f, ring) <- flatFaces st, (a, b) <- edges ring]
      facesOf a b = M.findWithDefault [] (key a b) owners
      cut = IS.fromList [e | EdgeId e <- candidates]
      joined = M.fromListWith (++) [(f, [g]) | (EdgeId e, a, b, _) <- flatEdges st, not (IS.member e cut), f <- facesOf a b, g <- facesOf a b, f /= g]
      reach seen [] = seen
      reach seen (f : rest)
        | f `elem` seen = reach seen rest
        | otherwise = reach (f : seen) (M.findWithDefault [] f joined ++ rest)
  first' <- case picked of
    f : _ -> Right f
    [] -> Left NothingSelected
  let moving = reach [] [first']
  if all (`elem` moving) picked then Right () else Left (SeedSplit (toSheetLengths st seed))
  let beside = [(e, letter, fs) | (e, a, b, letter) <- flatEdges st, e `elem` candidates, let fs = facesOf a b, any (`elem` moving) fs, any (`notElem` moving) fs]
  case [e | (e, Flat, _) <- beside] of
    e : _ -> Left (ExistingHingeFlat e)
    [] -> Right ()
  case beside of
    (_, _, fs) : _ | f : _ <- filter (`elem` moving) fs -> Right (Selection (nub moving) [h | (h, _, _) <- beside] f)
    _ -> Left NothingSelected
  where
    key a b = (min a b, max a b)

-- | The hinge as stretches of crease on the sheet, each with its edges: every
-- run of hinge edges joined end to end becomes one stretch, from end to end.
-- A fold through several layers has a stretch for each layer it turns.
hingeStretches :: FlatState -> [EdgeId] -> [(MaterialSegment, [EdgeId])]
hingeStretches st hinge = [found | group <- groups hinge, Just found <- [stretch group]]
  where
    ends e = [(a, b) | (e', a, b, _) <- flatEdges st, e' == e]
    touches g e = or [x == y | e' <- g, (a, b) <- ends e', (c, d) <- ends e, x <- [a, b], y <- [c, d]]
    groups = foldr place []
    place e gs = case [g | g <- gs, touches g e] of
      [] -> [e] : gs
      meeting -> (e : concat meeting) : filter (`notElem` meeting) gs
    stretch group = case [p | e <- group, (a, b) <- ends e, Just p <- [IM.lookup a (flatMaterial st), IM.lookup b (flatMaterial st)]] of
      points@(p : q : _) ->
        let along x = dot x (q ^-^ p)
         in Just (MaterialSegment (MaterialPoint (minimumBy (comparing along) points)) (MaterialPoint (minimumBy (comparing (negate . along)) points)), [e | e <- hinge, e `elem` group])
      _ -> Nothing
