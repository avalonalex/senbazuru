-- |
-- Module      : Senbazuru.Origami.FlatFold
-- Description : Maekawa's and Kawasaki's theorems, applied one vertex at a time.
--
-- == The question
--
-- A crease pattern is /flat-foldable/ if the sheet can be folded along its
-- creases into something that lies in a plane — every fold closed the whole way
-- to ±180°, like a map pressed shut. Most traditional models are flat-foldable.
-- Most sheets of paper with lines drawn on them are not.
--
-- Deciding it for a whole sheet is NP-hard, so nobody does; see
-- @docs\/notes\/flat-foldability-is-hard.md@. What is cheap is checking one
-- vertex at a time, and that is all this module attempts. Two classical
-- theorems each rule out a way a single vertex can fail:
--
-- * __Maekawa's__ — at an interior vertex of a flat-foldable pattern, the
--   number of mountains minus the number of valleys is exactly ±2. It follows
--   that the total is even, so a vertex with an odd number of creases is
--   hopeless whatever its angles. Counting is the entire algorithm: no
--   coordinates, no trigonometry, no tolerance.
--
-- * __Kawasaki's__ — walking around the vertex and adding the angles between
--   consecutive creases with alternating signs gives zero. This one needs
--   angles, and so needs a tolerance.
--
-- == What a clean result does and does not mean
--
-- Passing both is __necessary, not sufficient__, in two separate ways, and
-- conflating either with \"this folds flat\" is the mistake this module is
-- easiest to make:
--
-- 1. Kawasaki's theorem is an exact test of the /angles/: it says some
--    mountain-valley assignment folds this vertex flat. It does not say the
--    assignment in the file is that one. Maekawa constrains the /counts/ of
--    that assignment but not its arrangement, and a third local condition, the
--    Big-Little-Big lemma, constrains the arrangement — see
--    @docs\/notes\/big-little-big.md@. We do not check it yet.
--
-- 2. Every vertex passing says nothing about the sheet. Vertices that each fold
--    happily can still demand incompatible layer orders when folded together.
--
-- So 'Report' talks about violations found, never about foldability proved, and
-- the command line says the same. A vertex with no violations has survived the
-- checks we know how to make.
--
-- == What this can be pointed at
--
-- A crease pattern, and only a crease pattern. A frame with relief is a
-- three-dimensional folded form and is refused; so is a flat frame whose
-- @frame_classes@ says @foldedForm@, because a flat-folded model — the
-- traditional crane — has coordinates a crease pattern's cannot be told from,
-- and measuring one here would compare the angles the paper /ended up with/
-- against theorems about the ones it started from. That is not a missed check
-- but an invented one, which is worse. See 'requireCreasePattern'.
--
-- == Which lines count as creases
--
-- The theorems are about creases that actually fold, which is not the same as
-- edges in the file. This module sorts the assignments into three groups:
--
-- * @M@, @V@ and @U@ __divide the paper__ into sectors. @U@ is included because
--   an unassigned crease is one whose direction is not yet decided, not one
--   that does not fold — it still cuts the angle around the vertex in two.
--   Maekawa cannot be tested when any are present, since the counts are
--   unknown; Kawasaki still can, because it never looks at assignments.
--
-- * @F@ and @J@ are __dissolved__. A flat crease is drawn but not folded, and a
--   join says the two faces are really one piece of paper, so in both cases the
--   sectors on either side are a single sector. Failing to dissolve them is the
--   most likely way to get a wrong answer here: it inflates the crease count,
--   which flips the parity, and it splits one sector into two, which breaks the
--   alternating sum.
--
-- * @B@ and @C@ mean __the paper stops here__, so the vertex is skipped
--   entirely. Both theorems assume paper all the way round, and the angles at a
--   border vertex do not sum to a full turn — one of the sectors an algorithm
--   would compute is outside the sheet. A checker that forgets this reports a
--   violation at every point along the edge of the paper.
module Senbazuru.Origami.FlatFold
  ( -- * Checking a frame
    checkFrame,
    Report (..),
    reportViolations,
    VertexCheck (..),
    Violation (..),
    Skip (..),
    renderViolation,
    renderReport,

    -- * Errors
    CheckError (..),
    renderCheckError,

    -- * The creases around one vertex
    Star (..),
    Spoke (..),
    frameStars,

    -- * Tolerance
    Tolerance (..),
    defaultTolerance,
  )
where

import Data.Bifunctor (first)
import Data.Either (partitionEithers)
import Data.IntMap.Strict qualified as IM
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showFFloat, showGFloat)
import Senbazuru.Fold.Query
  ( Crease (..),
    FoldError (..),
    frameCreases,
    frameVertices,
    renderFoldError,
  )
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..), normalize)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, zSpan)

-- | How far the alternating sum of Kawasaki's theorem may sit from zero and
-- still count as zero, in radians.
--
-- Kept as a parameter rather than a constant because the right value depends on
-- the file, not on us. See 'defaultTolerance'.
newtype Tolerance = Tolerance {toleranceRadians :: Double}
  deriving stock (Eq, Show)

-- | 1e-5 radians, about 0.0006°.
--
-- The floor is set by the file, not by our arithmetic. Summing a handful of
-- angles costs about 1e-15 of accumulated rounding, which is nowhere near the
-- limit. What matters is that real files store rounded coordinates:
-- @examples\/squaretwist.fold@ gives them to six decimal places, and a
-- coordinate wrong by 5e-7 at the end of an edge of length 0.25 tilts that
-- edge's bearing by about 2e-6 radians. Eight sectors built from such bearings
-- can drift a few times 1e-6 from the exact answer, so a tolerance of 1e-6
-- would reject patterns that are correct as designed and merely written down
-- imprecisely.
--
-- The ceiling is set by what we want to catch. 0.0006° is far smaller than any
-- discrepancy a person could have meant, so a pattern that fails at this
-- tolerance is wrong rather than rounded.
--
-- A file rounded harder than six places needs a larger value, which is why the
-- command line takes one. The tolerance can be removed altogether by testing
-- Kawasaki's condition in exact arithmetic instead of trigonometry — see
-- @docs\/notes\/kawasaki-without-trig.md@ — which we have not done.
defaultTolerance :: Tolerance
defaultTolerance = Tolerance 1e-5

-- | Everything that stops a frame being checkable at all, as opposed to a
-- violation, which is a fact /about/ a checkable frame.
data CheckError
  = -- | The frame is not structurally sound enough to get this far.
    FrameGeometry !FoldError
  | -- | The geometry leaves the plane, so this is a three-dimensional folded
    -- form and not a pattern at all. Carries how far it spans in @z@.
    NotFlat !Double
  | -- | Flat, but @frame_classes@ says @foldedForm@: a flat-folded model such
    -- as the traditional crane, whose coordinates are indistinguishable from a
    -- crease pattern's.
    DeclaredFoldedForm
  | -- | The file records no @edges_assignment@ at all, so nothing can be said
    -- about which lines fold or where the paper stops. See
    -- 'requireAssignments'.
    NoAssignments
  | -- | An edge whose two endpoints are the same point, or whose coordinates
    -- are not finite. It has no direction, so it has no place in the rotational
    -- order around either endpoint.
    DegenerateEdge !EdgeId
  deriving stock (Eq, Show)

-- | A human-readable rendering of a 'CheckError', for a CLI message.
renderCheckError :: CheckError -> Text
renderCheckError = \case
  FrameGeometry err -> renderFoldError err
  NotFlat dz ->
    "the vertices span "
      <> general dz
      <> " in z, so this frame is a folded form; flat-foldability is a"
      <> " question about the crease pattern it was folded from"
  DeclaredFoldedForm ->
    "frame_classes says foldedForm. The coordinates are flat, but a"
      <> " flat-folded model looks exactly like a crease pattern and only the"
      <> " class tells them apart; checking this one would measure folded"
      <> " angles against theorems about unfolded ones"
  NoAssignments ->
    "no edges_assignment, so there is no way to tell a fold from the edge of"
      <> " the paper; every vertex would look like an interior one"
  DegenerateEdge (EdgeId e) ->
    "edge "
      <> tshow e
      <> " has no usable direction: its endpoints coincide, or a coordinate is"
      <> " not finite"

-- | One crease, as seen from a vertex it meets.
data Spoke = Spoke
  { spokeEdge :: !EdgeId,
    -- | Which way the crease leaves this vertex: the angle from the positive
    -- x axis, in radians, as 'atan2' gives it.
    spokeBearing :: !Double,
    spokeAssignment :: !Assignment
  }
  deriving stock (Eq, Show)

-- | Every crease meeting one vertex, in rotational order — its /star/.
data Star = Star
  { starVertex :: !VertexId,
    -- | The creases that fold, counterclockwise by bearing. @F@ and @J@ edges
    -- have been dissolved; @B@ and @C@ edges are absent too, but their presence
    -- is recorded in 'starOnBorder'.
    starSpokes :: ![Spoke],
    -- | The angle of paper between each spoke and the next one
    -- counterclockwise, in radians. Same length and order as 'starSpokes', and
    -- sums to @2 * pi@.
    starSectors :: ![Double],
    -- | Whether an edge of the paper, or a cut, reaches this vertex.
    starOnBorder :: !Bool,
    -- | How many @F@ or @J@ edges were dissolved. Kept so that a caller
    -- confronted with a surprising crease count can trace it back to them;
    -- nothing in senbazuru prints it yet.
    starDissolved :: !Int
  }
  deriving stock (Eq, Show)

-- | Why a vertex was not checked. Neither case is a complaint about the file.
data Skip
  = -- | The paper ends here, so the theorems do not apply.
    OnBorder
  | -- | Nothing folds here: an isolated vertex, or one where every incident
    -- edge is flat.
    NoCreases
  deriving stock (Eq, Show)

-- | A local condition that every flat-foldable vertex satisfies, and this one
-- does not.
data Violation
  = -- | Maekawa's corollary: an odd number of creases meet here. Carries the
    -- count. Reported instead of 'MaekawaImbalance' rather than as well as it,
    -- because an odd count is the more fundamental fact and it also leaves
    -- Kawasaki's alternating sum undefined.
    OddCreaseCount !Int
  | -- | Maekawa's theorem: mountains minus valleys is not ±2. Carries the
    -- mountain and valley counts.
    MaekawaImbalance !Int !Int
  | -- | Kawasaki's theorem: the alternating sum of the sector angles is not
    -- zero. Carries the sum, in degrees.
    KawasakiSum !Double
  deriving stock (Eq, Show)

-- | What we can say about one vertex we were able to check.
data VertexCheck = VertexCheck
  { checkVertex :: !VertexId,
    -- | Creases that fold, after dissolving. This is the number both theorems
    -- are about, and it can be smaller than the vertex's degree in the file.
    checkDegree :: !Int,
    -- | How many of those have assignment @U@. Maekawa is not tested when this
    -- is non-zero.
    checkUnassigned :: !Int,
    -- | Empty means nothing was found, which is weaker than \"folds flat\" —
    -- see the module header.
    checkViolations :: ![Violation]
  }
  deriving stock (Eq, Show)

-- | The outcome for a whole frame.
data Report = Report
  { reportChecked :: ![VertexCheck],
    reportSkipped :: ![(VertexId, Skip)]
  }
  deriving stock (Eq, Show)

-- | Every violation in a report, paired with the vertex it was found at.
reportViolations :: Report -> [(VertexId, Violation)]
reportViolations r =
  [(checkVertex c, v) | c <- reportChecked r, v <- checkViolations c]

-- | Check every interior vertex of a frame.
checkFrame :: Tolerance -> Frame -> Either CheckError Report
checkFrame tol fr = do
  stars <- frameStars fr
  let (skipped, checked) = partitionEithers (map (verdict tol) stars)
  pure (Report {reportChecked = checked, reportSkipped = skipped})

-- | Assemble the creases meeting every vertex of a frame, in rotational order.
--
-- The result has one entry per vertex in @vertices_coords@, in id order,
-- including vertices no edge mentions.
frameStars :: Frame -> Either CheckError [Star]
frameStars fr = do
  verts <- first FrameGeometry (frameVertices fr)
  -- An empty frame is refused rather than answered, so that `check` and
  -- `render` agree about a file whose vertices_coords went missing. A hook
  -- that passes such a file silently is worse than one that fails.
  if null verts then Left (FrameGeometry NoVertices) else Right ()
  requireCreasePattern fr verts
  requireAssignments fr
  creases <- first FrameGeometry (frameCreases fr)
  spokes <- concat <$> traverse spokesOf creases
  let byVertex = IM.fromListWith (<>) spokes
  pure
    [ starAt (VertexId i) (IM.findWithDefault [] i byVertex)
      | i <- [0 .. length verts - 1]
    ]

-- | Refuse a frame that is not a crease pattern.
--
-- Two tests, in the order 'Senbazuru.Render.CreasePattern.defaultNotationFor'
-- uses them and for the same reasons. Relief settles it: a frame that leaves
-- the plane is a folded form whatever it calls itself, and 'hasRelief' is the
-- one place that judgement is made, so the checker and the renderer cannot
-- disagree about the same file.
--
-- A flat frame is the hard case. A flat-folded model — the traditional crane —
-- has coordinates indistinguishable from a crease pattern's, so the only thing
-- left to ask is @frame_classes@, and a frame that declares nothing is taken as
-- a pattern, which is what the rest of senbazuru does.
--
-- Getting this wrong is not a missed check but an invented one. Run a folded
-- crane through Kawasaki's theorem and it reports violations at vertices that
-- are perfectly correct, because the angles being measured are the ones the
-- paper ended up with rather than the ones it was folded from.
requireCreasePattern :: Frame -> [V3] -> Either CheckError ()
requireCreasePattern fr verts
  | hasRelief verts = Left (NotFlat (zSpan verts))
  | "foldedForm" `elem` frameClasses fr = Left DeclaredFoldedForm
  | otherwise = Right ()

-- | Refuse a frame that records no @edges_assignment@ at all.
--
-- FOLD makes the array optional, and 'frameCreases' rightly reads its absence
-- as \"nothing is known about any crease\", which is exactly what @U@ means.
-- For drawing, that is harmless. Here it is fatal in a way that is easy to
-- miss: with no assignments there are no @B@ edges, so no vertex is recognised
-- as being on the border, and every vertex around the outside of the sheet gets
-- measured as though it had paper all the way round. A perfectly good square
-- then reports a violation at each of its boundary vertices — a checker
-- confidently declaring a correct file wrong, which is the worst thing it
-- could do.
--
-- One step of the same trap is still open: a file that marks its outline @U@
-- rather than @B@ cannot be told apart from one whose creases are genuinely
-- undecided, and violations are reported there. Working the boundary out from
-- the geometry would close both, and wants faces.
requireAssignments :: Frame -> Either CheckError ()
requireAssignments fr
  | null (edgesVertices fr) = Right ()
  | null (edgesAssignment fr) = Left NoAssignments
  | otherwise = Right ()

-- | The two spokes an edge contributes, one at each endpoint.
spokesOf :: Crease -> Either CheckError [(Int, [Spoke])]
spokesOf c =
  -- normalize is used only for its refusal to accept a zero-length or
  -- non-finite vector; the unit vector itself is not wanted, because a bearing
  -- is what puts spokes in rotational order.
  case normalize (V2 dx dy) of
    Nothing -> Left (DegenerateEdge (creaseId c))
    Just _ ->
      Right
        [ (unVertexId (creaseFrom c), [spoke (atan2 dy dx)]),
          (unVertexId (creaseTo c), [spoke (atan2 (-dy) (-dx))])
        ]
  where
    V3 ax ay _ = creaseStart c
    V3 bx by _ = creaseEnd c
    dx = bx - ax
    dy = by - ay
    spoke bearing = Spoke (creaseId c) bearing (creaseAssignment c)

-- | Sort one vertex's spokes and measure the sectors between them.
starAt :: VertexId -> [Spoke] -> Star
starAt vid spokes =
  Star
    { starVertex = vid,
      starSpokes = folding,
      starSectors = sectorsBetween (map spokeBearing folding),
      starOnBorder = any (paperEndsAt . spokeAssignment) spokes,
      starDissolved = length (filter (doesNotFold . spokeAssignment) spokes)
    }
  where
    folding = sortOn spokeBearing (filter (foldsHere . spokeAssignment) spokes)

-- | @B@ and @C@: the sheet, or this part of it, stops here.
paperEndsAt :: Assignment -> Bool
paperEndsAt = \case
  Border -> True
  Cut -> True
  _ -> False

-- | @M@, @V@ and @U@: a line the paper may fold along, so it divides the angle
-- around the vertex.
foldsHere :: Assignment -> Bool
foldsHere = \case
  Mountain -> True
  Valley -> True
  Unassigned -> True
  _ -> False

-- | @F@ and @J@: drawn, but the paper is continuous across it.
doesNotFold :: Assignment -> Bool
doesNotFold = \case
  Flat -> True
  Join -> True
  _ -> False

-- | Angles between consecutive bearings, given in ascending order, wrapping
-- from the last back round to the first. Sums to @2 * pi@.
sectorsBetween :: [Double] -> [Double]
sectorsBetween [] = []
-- One crease, so there is one sector and it is the whole turn. Without this
-- case the general formula compares the single bearing with itself and yields
-- 0, which is the one input where the wrap-around is a full circle rather than
-- a remainder.
sectorsBetween [_] = [2 * pi]
sectorsBetween bearings = zipWith gap bearings (drop 1 bearings <> take 1 bearings)
  where
    gap a b
      | turn < 0 = turn + 2 * pi
      | otherwise = turn
      where
        turn = b - a

-- | @s0 - s1 + s2 - ...@, which Kawasaki's theorem says is zero.
--
-- The sign flips if you start one crease further round, since that shifts every
-- term from an odd position to an even one. Only the distance from zero means
-- anything, and that is what 'verdict' compares against the tolerance.
alternatingSum :: [Double] -> Double
alternatingSum = sum . zipWith (*) (cycle [1, -1])

-- | Apply both theorems to one vertex, or say why neither applies.
verdict :: Tolerance -> Star -> Either (VertexId, Skip) VertexCheck
verdict tol st
  | starOnBorder st = Left (starVertex st, OnBorder)
  | null (starSpokes st) = Left (starVertex st, NoCreases)
  | otherwise =
      Right
        VertexCheck
          { checkVertex = starVertex st,
            checkDegree = degree,
            checkUnassigned = unassigned,
            checkViolations = violations
          }
  where
    spokes = starSpokes st
    degree = length spokes
    countOf a = length (filter ((== a) . spokeAssignment) spokes)
    mountains = countOf Mountain
    valleys = countOf Valley
    unassigned = countOf Unassigned

    violations
      | odd degree = [OddCreaseCount degree]
      | otherwise = maekawa <> kawasaki

    maekawa
      | unassigned > 0 = []
      | abs (mountains - valleys) /= 2 = [MaekawaImbalance mountains valleys]
      | otherwise = []

    kawasaki
      | abs sum' > toleranceRadians tol = [KawasakiSum (degrees sum')]
      | otherwise = []
      where
        sum' = alternatingSum (starSectors st)

-- | A one-line description of a violation, naming the vertex and the theorem.
--
-- Kept to one terminal line each. The reasoning behind them belongs in the
-- README and in @docs\/notes\/@, not in a message someone reads once per run.
renderViolation :: VertexId -> Violation -> Text
renderViolation (VertexId v) = \case
  OddCreaseCount n ->
    at <> tshow n <> " creases meet here, an odd number, which never folds flat (Maekawa)"
  MaekawaImbalance m val ->
    at
      <> tshow m
      <> " mountains and "
      <> tshow val
      <> " valleys, which must differ by 2 (Maekawa)"
  KawasakiSum s ->
    at <> "sector angles alternate to " <> fixed 4 s <> " degrees, not 0 (Kawasaki)"
  where
    at = "vertex " <> tshow v <> ": "

-- | A report as lines of text: one per violation, then a summary.
--
-- Lives here rather than in the command line for two reasons. It is the wording
-- that keeps the promise the module header makes — \"no violations found\",
-- never \"flat-foldable\" — and it has enough branching to be worth a test,
-- which "Senbazuru.Cli" says of itself that it does not.
renderReport :: Report -> [Text]
renderReport report = violationLines <> [checkedLine, verdictLine]
  where
    violations = reportViolations report
    violationLines = [renderViolation v x | (v, x) <- violations]

    checkedLine =
      "checked "
        <> plural (length (reportChecked report)) "interior vertex" "interior vertices"
        <> skippedNote

    verdictLine
      | null violations = "no violations found"
      | otherwise = plural (length violations) "violation" "violations"

    skippedNote = case (countSkips OnBorder, countSkips NoCreases) of
      (0, 0) -> ""
      (border, 0) -> "; skipped " <> tshow border <> " on the border"
      (0, bare) -> "; skipped " <> tshow bare <> " with no creases"
      (border, bare) ->
        "; skipped "
          <> tshow border
          <> " on the border and "
          <> tshow bare
          <> " with no creases"

    countSkips s = length [() | (_, s') <- reportSkipped report, s' == s]

    plural n one several = tshow n <> " " <> (if n == 1 then one else several)

degrees :: Double -> Double
degrees r = r * 180 / pi

-- | Fixed-point, so a message never reads @1.0e-2@.
fixed :: Int -> Double -> Text
fixed places x = T.pack (showFFloat (Just places) x "")

-- | Fixed-point for numbers of ordinary size, exponent notation below 0.1.
--
-- Used where the value reported may be tiny. 'hasRelief' judges flatness
-- relative to the sheet, so a 400-unit pattern can be refused over a @z@ span of
-- 1e-6, and printing that as @0.000000@ would tell the reader their file is a
-- folded form because a coordinate is off by nothing at all.
general :: Double -> Text
general x = T.pack (showGFloat (Just 6) x "")

tshow :: (Show a) => a -> Text
tshow = T.pack . show
