-- |
-- Module      : Senbazuru.Origami.ThroughLayers
-- Description : Creasing a model that is already folded, through its layers.
--
-- "Senbazuru.Fold.Creasing" draws a line on a flat sheet. This draws one on a
-- model that has already been folded, which is how a book actually gives its
-- instructions: step 4 says \"fold the top corner down\" about paper that was
-- folded in half in step 2, and the reader's fingers are creasing every layer
-- under the line at once.
--
-- == One segment per face, not one crease per layer
--
-- A line drawn across a folded model is not one crease and it is not one crease
-- per layer either. The paper under the line is a set of /faces/, each of which
-- arrived there by a different fold, so each becomes a different line on the
-- flat sheet. The count is therefore the number of faces the line crosses,
-- which is bounded by the number of faces and by nothing smaller: a line across
-- the folded crane crosses 56 of its 72, where the deepest stack of paper found
-- over any one point is 24 and the largest layer number is 32. Those are three
-- different questions and only the first one is this one.
--
-- Most of the 56 are short pieces of a handful of creases, cut up by the
-- creases the pattern already has, so \"56 creases\" would overstate what a
-- person would say they had drawn.
--
-- == Why the flat pattern stays in charge
--
-- The move is expressed on the sheet and uses the folded model only to say
-- /where/. Fold the pattern, work out what the line becomes on the sheet, and
-- crease the sheet — so there is one authoritative representation and it is the
-- one @docs\/notes\/fold-angles-are-the-state.md@ argues the state actually is.
--
-- The alternative, creasing the folded form directly and folding backwards,
-- leaves the model in two representations at once with no answer to which wins.
--
-- == The line that is not a mistake: half the creases come out the other kind
--
-- Ask for a valley and about half of what gets written is a __mountain__, and
-- that is correct. Every layer of a packet creases the same physical way, but
-- alternate layers are upside down — a flap folded over shows the underside of
-- the paper — so a fold that opens towards the reader is a valley on the faces
-- lying top-up and a mountain on the ones lying top-down. Fold a square in half
-- and crease the packet, and unfolding gives you one of each. Passing the
-- caller's assignment through unchanged would produce a file that looks right
-- and folds into a different model.
--
-- Which way up a face lies is read from the motion that placed it, as where it
-- sends the up direction. A flat fold sends it to exactly plus or minus itself
-- and nothing in between, so the sign is the whole answer. Deliberately /not/
-- from "Senbazuru.Origami.Flat"'s @panelFaceUp@, which reads the winding the
-- file wrote — a guess with nothing to cancel against, per CLAUDE.md. The
-- motion is a measurement.
--
-- == What it will not do
--
-- __Every layer under the line is creased.__ A book distinguishes folding
-- through all the layers from folding only the near ones, and that second
-- instruction is a different move belonging with the
-- <https://github.com/avalonalex/senbazuru/issues/60 vocabulary>. It would also
-- need to know which face is over which at a point, which is a depth question
-- this deliberately never asks.
--
-- __Flat-folded models only.__ On a model with paper still in the air, a line
-- drawn on the page is a ray rather than a point and has no single place it
-- came from. That is the same restriction "Senbazuru.Origami.Visible" and the
-- layer solver carry, and it arrives here for free from
-- 'Senbazuru.Origami.Flat.flatSheet'.
--
-- __Neither end may be in the middle of a face.__ That layer would be creased
-- only part of the way across, and a crease that stops in the middle of the
-- paper divides nothing. Refused by name, as 'LineStopsOnTheModel'.
--
-- Note what that does /not/ say. The test is per face and not about the model:
-- an end on the boundary of every face it touches is fine wherever it is,
-- including well inside the model's silhouette, because every one of those
-- layers is then creased edge to edge. Whether a given crease of a folded model
-- is such a place depends on whether the layers' edges coincide there, and that
-- varies more than it sounds. Of the folded crane's 248 face-edge midpoints,
-- 120 are on the boundary of every face they touch and 128 are inside some
-- other face and refused; the bird base splits 24 to 20; the quarter fold, whose
-- four layers land exactly on top of one another, is 16 to nothing.
module Senbazuru.Origami.ThroughLayers
  ( creaseThroughLayers,
    ThroughError (..),
    renderThroughError,
  )
where

import Control.Monad (guard, when)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showGFloat)
import Senbazuru.Fold.Creasing (creaseAllAlong)
import Senbazuru.Fold.Query (CreaseEnd (..), FoldError (..), creaseEndFlag, renderFoldError)
import Senbazuru.Fold.Types (Assignment (..), FaceId (..), Frame (..))
import Senbazuru.Geometry (V2 (..), norm, (^+^), (^-^))
import Senbazuru.Geometry.Polygon (clipSegment, strictlyInside)
import Senbazuru.Geometry.Rigid (Rigid, applyRigid, inverse, matApply, rigidLinear)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace ((*^))
import Senbazuru.Origami.Flat (FlatError (..), Panel (..), Sheet (..), flatSheet)
import Senbazuru.Origami.Folding
  ( Folded (..),
    FoldingError,
    foldFrameWith,
    renderFoldingError,
  )

-- | Everything that stops a line drawn on a folded model becoming creases.
data ThroughError
  = -- | The pattern could not be folded, so there is no model to draw on. The
    -- commonest one by far is a frame that is /already/ a folded form: such a
    -- file records no angles to fold and no sheet to map back to, and
    -- recovering one would be unfolding, which is a different problem.
    CannotFold !FoldingError
  | -- | The model does not come back into one plane, so a line drawn on the
    -- page passes through several thicknesses of paper at different heights
    -- and does not name one point on any of them. Carries the span in @z@.
    PaperStillInTheAir !Double
  | -- | A face is not convex, and clipping a line to it is only right for ones
    -- that are.
    FaceNotConvex !FaceId
  | -- | The folded model is unsound in a way that has nothing to do with this
    -- move.
    ThroughRefused !FoldError
  | -- | The two ends given are the same point, so there is no line.
    LineWithoutLength
  | -- | Nothing was creased: either the line misses the model, or it runs along
    -- the model's edges rather than across its paper. Both leave no face with a
    -- stretch of line properly inside it.
    NoPaperUnderTheLine
  | -- | An end of the line is inside one of the model's faces rather than on
    -- that face's edge, so the crease that layer gets would stop in the middle
    -- of its own paper. Carries which end, and a face it landed in.
    --
    -- Asked of each face and not of the model as a whole, which is the tempting
    -- generalisation and is the wrong question. What has to be true is that
    -- /every layer the line reaches is creased right across/, and that is a fact
    -- about each face separately. An end well inside the model's silhouette is
    -- perfectly good so long as it is on the boundary of every face it touches
    -- — which is what happens where a fold has brought several layers' edges
    -- into line, and is why the quarter fold accepts an end on any of its
    -- creases.
    --
    -- It is not the common case, though, and saying so would be wrong: on the
    -- folded crane 128 of 248 face-edge midpoints are inside some other face,
    -- because one layer's crease crosses the middle of another layer's paper.
    -- Those are refused, and correctly.
    --
    -- Unlike "Senbazuru.Fold.Creasing", which has no way to say where a sheet
    -- /is/ and says so, this can ask: the folded model is a list of convex
    -- panels and the question is one predicate on each.
    LineStopsOnTheModel !CreaseEnd !FaceId
  | -- | A face of the folded model has no motion recorded for it, so there is
    -- no way to take its share of the line back to the sheet.
    --
    -- 'Senbazuru.Origami.Folding.Folded' promises this cannot happen — a face
    -- the walk could not reach is a @DisconnectedFace@ and the fold fails
    -- instead. It is refused here anyway because the alternative is not an
    -- error but a /wrong answer/: skipping the face would crease some layers
    -- and not others, hand back a pattern that folds into a different model,
    -- and report success. An invariant held in another module is a fine reason
    -- to expect something and a poor reason to assume it.
    LayerNotPlaced !FaceId
  | -- | The lines this move worked out were refused when they were drawn on
    -- the sheet.
    --
    -- No face. They are drawn in one go, and the cutting that refuses them sees
    -- all of them at once, so a refusal is about the set and not about one
    -- layer — and saying otherwise would mean naming whichever share the cutter
    -- happened to reach first. What "Senbazuru.Fold.Creasing" says names the
    -- point at fault where it can, which locates the share better than a face
    -- number would.
    CannotCrease !FoldError
  deriving stock (Eq, Show)

-- | A human-readable rendering of a 'ThroughError'.
renderThroughError :: ThroughError -> Text
renderThroughError = \case
  CannotFold err -> renderFoldingError err
  PaperStillInTheAir dz ->
    "the folded model spans "
      <> num dz
      <> " in z, so it is not folded flat and a line drawn on it does not name"
      <> " one point of the paper"
  FaceNotConvex (FaceId f) ->
    "face " <> tshow f <> " is not convex, so the line cannot be clipped to it"
  ThroughRefused err -> renderFoldError err
  LineWithoutLength ->
    "the two ends are the same point, so they name no line to crease along"
  NoPaperUnderTheLine ->
    "no face of the folded model has this line across it, so there is nothing"
      <> " to crease: either it misses the model or it runs along its edges"
  LineStopsOnTheModel end (FaceId f) ->
    creaseEndFlag end
      <> " is inside face "
      <> tshow f
      <> " of the folded model rather than on that face's edge, so that layer"
      <> " would be creased only part of the way across. Each layer the line"
      <> " reaches has to be creased right across, so move this end onto an edge"
      <> " or clear of the paper"
  LayerNotPlaced (FaceId f) ->
    "face "
      <> tshow f
      <> " of the folded model has no motion recorded for it, so there is no way"
      <> " to say where its share of this line came from on the sheet"
  CannotCrease err ->
    "the creases this line makes on the layers it reaches were refused: "
      <> renderFoldError err

-- | Draw a line on a folded model and crease every layer under it.
--
-- @creaseThroughLayers from to assignment pattern@ takes a crease pattern with
-- fold angles, folds it, reads the two points __in the folded model's
-- coordinates__, and hands back the pattern with the creases that line makes on
-- the sheet. What comes back is a crease pattern, never a folded form: the
-- caller folds it again to see the result.
--
-- The assignment asked for is the one a reader would name looking at the model
-- from @+z@, which is where a crease pattern is drawn from and how mountain and
-- valley are defined. Layers lying face down get the other one — see the module
-- header, because that is the part that looks wrong and is not.
creaseThroughLayers :: V2 -> V2 -> Assignment -> Frame -> Either ThroughError Frame
creaseThroughLayers from to assignment fr = do
  folded <- first CannotFold (foldFrameWith fr)
  -- Of the folded form, not of the pattern: the rings the line is clipped
  -- against are where the paper is now. This is also the one refusal that has
  -- to happen before anything else is measured, since a model with paper in the
  -- air has no plane for the line to be drawn on.
  sheet <- first fromFlat (flatSheet (foldedFrame folded))
  -- Judged by the folded model's own tolerance, so that "the same point" means
  -- here what it means everywhere else on this paper.
  when (norm (to ^-^ from) <= sheetHair sheet) (Left LineWithoutLength)
  -- Asked of the ends before anything is clipped, because a clip cannot tell
  -- the difference: a line stopping halfway over the model comes back from
  -- 'clipSegment' looking exactly like one that crossed a narrow face.
  case [ (which, panelId p)
         | (which, end) <- [(FromEnd, from), (ToEnd, to)],
           p <- sheetPanels sheet,
           stopsOn sheet p end
       ] of
    ((which, f) : _) -> Left (LineStopsOnTheModel which f)
    [] -> Right ()
  -- Asked once, up front, rather than folded into the per-face Maybe below,
  -- where "no motion for this face" would be indistinguishable from "the line
  -- misses this face" and would silently drop a layer.
  case [panelId p | p <- sheetPanels sheet, not (hasPlacement (foldedPlacements folded) p)] of
    (f : _) -> Left (LayerNotPlaced f)
    [] -> Right ()
  let shares = mapMaybe (shareFor sheet (foldedPlacements folded) assignment (from, to)) (sheetPanels sheet)
  when (null shares) (Left NoPaperUnderTheLine)
  -- One call, not one per layer. Drawing them in turn meant cutting and
  -- re-tracing the whole pattern once per share, which is most of the work and
  -- all of the cost: a 320-fold accordion took a minute where the fold itself
  -- takes a third of a second. It is also unnecessary -- the shares are points
  -- on a sheet that does not move while they are drawn. See #77.
  first CannotCrease $
    creaseAllAlong
      [(layerFrom share, layerTo share, layerAs share) | share <- shares]
      (foldedPattern folded)

-- | One layer's share of the line: where it lands on the sheet, and what kind
-- of crease it is there.
data LayerCrease = LayerCrease
  { layerFace :: !FaceId,
    layerFrom :: !V2,
    layerTo :: !V2,
    layerAs :: !Assignment
  }
  deriving stock (Eq, Show)

-- | What the drawn line becomes on one face's worth of paper, if it crosses it.
--
-- The two tests are one question asked twice, and both are needed.
-- 'clipSegment' hands back a segment lying exactly /along/ an edge of the ring
-- whole, because such a segment is inside the polygon by the boundary-included
-- reading it uses. That is a line drawn down the fold rather than across the
-- paper, and creasing along a crease that is already there is refused later
-- anyway, less clearly. So the midpoint is asked whether it is properly inside.
-- The length test catches the other degenerate clip, where the line only grazes
-- a corner. "Senbazuru.Origami.Stacking"'s @runsAcross@ is the same pair.
shareFor :: Sheet -> IM.IntMap Rigid -> Assignment -> (V2, V2) -> Panel -> Maybe LayerCrease
shareFor sheet placements assignment line panel = do
  placed <- IM.lookup (unFaceId (panelId panel)) placements
  (u, v) <- clipSegment (panelRing panel) line
  guard (norm (v ^-^ u) > sheetHair sheet)
  guard (strictlyInside (sheetHair sheet) (panelRing panel) (0.5 *^ (u ^+^ v)))
  let back = inverse placed
  pure
    LayerCrease
      { layerFace = panelId panel,
        layerFrom = ontoSheet back u,
        layerTo = ontoSheet back v,
        layerAs = if facesUp placed then assignment else theOtherWay assignment
      }
  where
    -- Out of the plane the model lies in, back through the fold, and into the
    -- plane the pattern lies in. The z that comes back is nought to within
    -- rounding, since undoing a flat fold lands in the plane the sheet was cut
    -- from, and dropping it is what makes this a crease pattern coordinate
    -- again.
    ontoSheet back (V2 x y) = case applyRigid back (V3 x y (sheetPlane sheet)) of
      V3 x' y' _ -> V2 x' y'

-- | Whether the fold recorded a motion for this face.
hasPlacement :: IM.IntMap Rigid -> Panel -> Bool
hasPlacement placements panel = IM.member (unFaceId (panelId panel)) placements

-- | Whether an end of the drawn line came down on this face's paper.
--
-- Strictly inside, so an end that lands on the silhouette or on a crease is
-- fine: the crease it makes there runs to the edge of that layer's paper, which
-- is what a fold does. It is an end in the /middle/ of a face that has no
-- meaning, and the clearance is the same hair everything else on this model is
-- judged by.
stopsOn :: Sheet -> Panel -> V2 -> Bool
stopsOn sheet panel = strictlyInside (sheetHair sheet) (panelRing panel)

-- | Whether this face still has the top side of the paper towards @+z@.
--
-- Where the motion sends the up direction. For a model folded flat that is
-- exactly @+z@ or exactly @-z@ — every turn is by a half circle about a line in
-- the plane, and those map the up direction to plus or minus itself — so the
-- sign is the whole answer and there is no near-tie to get wrong.
facesUp :: Rigid -> Bool
facesUp placed = v3z (matApply (rigidLinear placed) (V3 0 0 1)) > 0

-- | The same fold seen from the other side of the paper.
--
-- Only mountain and valley have another side. A border is a border whichever
-- way the paper is turned; and flat and unassigned say the paper does not fold
-- there, or that nobody has decided, and neither of those has a direction to
-- reverse.
theOtherWay :: Assignment -> Assignment
theOtherWay = \case
  Mountain -> Valley
  Valley -> Mountain
  other -> other

-- | A 'FlatError' as this module's own refusal.
--
-- Flattened rather than wrapped, the way "Senbazuru.Origami.Stacking" does it:
-- what stops this move is a fact about the model, and it reads better said in
-- this module's words than as another error type quoted inside one.
fromFlat :: FlatError -> ThroughError
fromFlat = \case
  PaperInTheAir dz -> PaperStillInTheAir dz
  ConcaveFace f -> FaceNotConvex f
  FlatRefused err -> ThroughRefused err

num :: Double -> Text
num x = T.pack (showGFloat (Just 6) x "")

tshow :: (Show a) => a -> Text
tshow = T.pack . show
