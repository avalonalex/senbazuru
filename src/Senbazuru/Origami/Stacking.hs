-- |
-- Module      : Senbazuru.Origami.Stacking
-- Description : Working out which layer is on top when the file does not say.
--
-- A folded model overlaps itself, and a picture of one is only right if the
-- faces are painted back to front. FOLD records back-to-front in @faceOrders@,
-- and "Senbazuru.Origami.Layers" reads it. This module is for the file that
-- has none — above all the folded form "Senbazuru.Origami.Folding" produces,
-- which knows where every face went and nothing about which is in front.
--
-- Deciding that is a constraint problem, and in general a hard one
-- (@docs\/notes\/layer-ordering.md@). It is tractable here for two reasons: the
-- models are small, and the constraints are local. Every rule below is about a
-- handful of faces that share a patch of paper or an edge, and most pairs of
-- faces share neither.
--
-- == Only flat-folded models, and only convex faces
--
-- This solver takes a model that lies entirely in one plane, which is what a
-- traditional model folded to completion does. Then \"above\" means one thing —
-- nearer @+z@ — and every question about overlap is a question about polygons
-- in the plane. A model with paper still in the air is refused with 'NotFlat',
-- and the caller draws it as it always has. Faces have to be convex because the
-- overlap test ("Senbazuru.Geometry.Polygon") is only right for convex
-- polygons; Kawasaki's theorem makes the faces of a flat-foldable pattern
-- convex whenever the sheet is, so this refuses very little in practice.
--
-- Both of those judgements, and the reading of the frame that goes with them,
-- are "Senbazuru.Origami.Flat" — shared with the visible-region finder, which
-- covers exactly the same models for exactly the same reasons.
--
-- == The variables
--
-- One yes-or-no per pair of faces whose interiors overlap: is the first above
-- the second? Two faces in one plane that overlap at all are ordered the same
-- way everywhere they overlap — one would have to pass through the other to
-- swap — so one bit per pair is the whole state. Pairs that do not overlap get
-- no variable and no entry in the answer, which is how FOLD says the same
-- thing.
--
-- == The rules
--
-- Four kinds, and the first three have names in the literature. Two faces
-- joined along an edge of the folded form are either a __taco__ — the paper
-- folded back on itself, both faces on one side of the edge — or a
-- __tortilla__, paper continuing flat across the line. Everything the paper
-- forbids can be said in those terms:
--
-- 1. __The crease itself__ ('Fixed'). A taco's two faces overlap, and its
--    assignment says which is on top. A valley brings the two /top/ sides
--    together, so the face whose top faces down is above the face whose top
--    faces up; a mountain is the reverse.
--
-- 2. __Taco-tortilla__ ('NotBetween'). A face that runs across a taco's fold
--    line cannot lie between the taco's two faces: the paper is continuous
--    across the line, and the fold would have to pass through it.
--
-- 3. __Taco-taco__ ('NoInterleave'). Two tacos folded on the same line, on the
--    same side, must nest or stay apart. If one face of a taco is between the
--    other taco's faces, so is its partner.
--
-- 4. __Tortilla-tortilla__ ('SameOrder'). Two sheets continuing flat across
--    the same line cannot cross it in opposite orders. A face that runs across
--    a tortilla's line is itself a tortilla whose two halves are one face, so
--    it is filed here, with that face on both sides.
--
-- Plus one rule that is not about paper but about arithmetic: three faces that
-- share a patch of paper are totally ordered over it, so their three pairwise
-- bits may not run in a circle ('Acyclic'). It is only stated for triples with
-- a __common__ patch. Three faces can overlap pairwise with no point under all
-- three — the flaps of a twist do — and then a circle is exactly what the paper
-- does.
--
-- == Solving
--
-- Propagate, then guess. Every rule with at most one unknown decides that
-- unknown or reports a contradiction; when nothing more follows, the lowest
-- unassigned pair is set to \"first face above\", and if that leads to a
-- contradiction the other way is tried. Which solution comes out when several
-- are valid is therefore fixed by the face ids, and reproducible, which the
-- golden tests depend on. A contradiction with no guesses left to unmake is
-- 'Unstackable', and it names the rule's faces.
--
-- == The winding is trusted here, and 'foldFrame' makes it trustworthy
--
-- Whether a face lies top-up or top-down in the folded form is read from its
-- winding, exactly as "Senbazuru.Origami.Layers" does: FOLD defines a face's
-- normal by the order of @faces_vertices@, and a folded form is where that
-- definition does work. The file is checked against itself — across a taco the
-- two faces must wind opposite ways, across a tortilla the same — and a
-- disagreement is 'WindingClash' rather than a guess. 'foldFrame' writes its
-- faces counterclockwise as measured on the crease pattern, so the frames this
-- module was built for always pass.
-- == Where the time goes
--
-- The cost is the propagation, not the geometry, and only a profile says so.
-- On a 161-layer accordion the whole triple enumeration — every one of the
-- C(f, 3) 'Acyclic' rules — is 0.9% of the run, while looking pairs up in the
-- decided-pairs map is over half (#88). Two things measured in GHCi said the
-- opposite and were both wrong: the interpreter does not float the
-- loop-invariant clip out that a compiled build does, so an "optimisation"
-- worth 2× interpreted was worth nothing compiled. Measure with
-- @stack build --profile@ and @+RTS -p@; a proxy measurement here has misled
-- twice.
module Senbazuru.Origami.Stacking
  ( solveStacking,
    StackingError (..),
    renderStackingError,

    -- * Choosing among several
    Stackings (..),
    Choice (..),
    stackingSpace,
    layerOrderFor,
    solveStackingAs,
    componentCount,
    stateCount,

    -- * How hard to look
    Budget (..),
    defaultBudget,

    -- * The constraints
    Rule (..),
    stackingRules,
  )
where

import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (foldl', nub, tails)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Data.Set qualified as S
import Data.Text (Text)
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Query (Crease (..), EdgeKey, FoldError (..), edgeKey, facesAlongEdges, frameFaceOrders)
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FaceOrder (..),
    Frame (..),
    Stacking (..),
    VertexId (..),
  )
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (FlatError (..), Panel (..), Sheet (..), flatSheet, vertexAt)

-- | How many guesses the solver may make in one component before giving up.
--
-- A guess is one decision the search makes for itself: propagation runs first
-- and settles everything that follows from the rules, and only what is left
-- over is guessed at. Counted rather than timed, so the same file behaves the
-- same on every machine.
--
-- Propagation itself is not capped. Each step decides at least one pair and no
-- pair is ever decided twice, so it cannot run longer than there are pairs.
--
-- Per component rather than per model, which is the honest unit once the
-- components are solved separately: a model does not become harder by having
-- more independent easy pieces. It does bound the whole model at components
-- times budget.
newtype Budget = Budget {budgetGuesses :: Int}
  deriving stock (Eq, Show)

-- | A thousand guesses per component.
--
-- Chosen against measurement rather than picked as a round number, though it is
-- one. Of the models here, propagation alone settles the quarter fold, the
-- letter fold and the thirds pinwheel outright; the 2×2 grid spends two guesses
-- in each of its four open components, the kabuto four in each of its two, and
-- the crane — the largest, at 892 pairs — eight. The two models that cannot be
-- stacked at all are refused by propagation without a guess being made. A
-- thousand is therefore more than a hundred times the worst anything real has
-- asked for.
--
-- It bounds /work/, not time, and that is the point of counting guesses: the
-- same file behaves the same way on every machine. A guess costs about one
-- propagation sweep, so what a thousand of them cost depends on the model —
-- the crane's whole solve, analysis and propagation and its eight guesses
-- together, is about 60ms.
defaultBudget :: Budget
defaultBudget = Budget 1000

-- | Why no ordering was produced.
--
-- The first two mean nothing was attempted: the model is outside what this
-- solver covers, and nothing is known about it either way. The third means the
-- frame itself is wrong in a way no ordering could be right about.
data StackingError
  = -- | The model leaves the plane. Ordering the layers of a model that is
    -- still in the air is not implemented. Carries how far it spans in @z@.
    NotFlat !Double
  | -- | A face is not convex, and the overlap test is only right for convex
    -- polygons.
    NonConvexFace !FaceId
  | -- | A caller asked for a layer order a component does not have. Carries
    -- the component, the index asked for, and how many orders it has.
    NoSuchStacking !Int !Int !Int
  | -- | A caller gave an index for a component that does not exist. Carries
    -- the index and how many components have a choice in them at all.
    NoSuchComponent !Int !Int
  | -- | The frame is unsound, or its layers cannot be stacked at all.
    StackingRefused !FoldError
  deriving stock (Eq, Show)

instance Explain StackingError where
  explain = \case
    NotFlat dz ->
      "the model spans "
        <> num dz
        <> " in z; working out which layer is on top is only implemented for"
        <> " models folded flat"
    NoSuchComponent given have ->
      "there is no component "
        <> tshow given
        <> " to choose an order for: "
        <> ( if have == 0
               then "every part of this model has only one"
               else "only " <> tshow have <> " of them have more than one, numbered 0 to " <> tshow (have - 1)
           )
    NoSuchStacking component want have ->
      "there is no layer order "
        <> tshow want
        <> " for component "
        <> tshow component
        <> ", which has "
        <> tshow have
        <> (if have == 1 then " order, numbered 0" else " orders, numbered 0 to " <> tshow (have - 1))
    NonConvexFace (FaceId f) ->
      "face "
        <> tshow f
        <> " is not convex, and the test for whether two faces overlap is only"
        <> " right for convex ones"
    StackingRefused err -> explain err

-- | 'explain' for a 'StackingError', under the name it had before the class.
--
-- Kept when the class arrived so that nothing had to move at once. Nothing
-- calls it now: the CLI says 'explain' and no test names this one, so it is
-- exported for a caller that does not exist yet.
renderStackingError :: StackingError -> Text
renderStackingError = explain

-- | One constraint on the layer order, over the faces it names.
--
-- Each says which pairs it relates and what it forbids; 'ruleHolds' is the
-- meaning. They are exposed so that a test can check what a model /generates/
-- separately from whether it can be solved.
data Rule
  = -- | @Fixed a b v@: @a@ is above @b@ exactly when @v@. The crease's own
    -- assignment, for the two faces of a taco.
    Fixed FaceId FaceId Bool
  | -- | @NotBetween t a b@: @t@ is above both @a@ and @b@, or below both.
    -- Taco-tortilla: @t@ runs across the line @a@ and @b@ meet along.
    NotBetween FaceId FaceId FaceId
  | -- | @SameOrder a c b d@: @a@ is above @c@ exactly when @b@ is above @d@.
    -- Tortilla-tortilla: @a@–@b@ and @c@–@d@ both continue flat across one
    -- line, @a@ and @c@ on the same side of it. @c@ and @d@ may be the same
    -- face: a face the line runs through is a tortilla whose two halves are
    -- one face, and then this says it lies above the sheet or below it, not
    -- between.
    SameOrder FaceId FaceId FaceId FaceId
  | -- | @NoInterleave a b c d@: @c@ lies between @a@ and @b@ exactly when @d@
    -- does. Taco-taco: @a@–@b@ and @c@–@d@ are folded on one line, on the
    -- same side.
    NoInterleave FaceId FaceId FaceId FaceId
  | -- | @Acyclic a b c@: the three pairwise orders do not run in a circle.
    -- Stated only for three faces that share a patch of paper.
    Acyclic FaceId FaceId FaceId
  deriving stock (Eq, Show)

-- | The pairs of faces a rule relates, each as @(lower id, higher id)@.
rulePairs :: Rule -> [(FaceId, FaceId)]
rulePairs = \case
  Fixed a b _ -> [pair a b]
  NotBetween t a b -> [pair t a, pair t b]
  SameOrder a c b d -> [pair a c, pair b d]
  NoInterleave a b c d -> [pair a c, pair b c, pair a d, pair b d]
  Acyclic a b c -> [pair a b, pair b c, pair a c]

-- | Every face a rule mentions, once each, for naming the culprits.
ruleFaces :: Rule -> [FaceId]
ruleFaces =
  nub . \case
    Fixed a b _ -> [a, b]
    NotBetween t a b -> [t, a, b]
    SameOrder a c b d -> [a, c, b, d]
    NoInterleave a b c d -> [a, b, c, d]
    Acyclic a b c -> [a, b, c]

-- | Does the rule hold, given a way to ask whether one face is above another?
ruleHolds :: (FaceId -> FaceId -> Bool) -> Rule -> Bool
ruleHolds above = \case
  Fixed a b v -> above a b == v
  NotBetween t a b -> above t a == above t b
  SameOrder a c b d -> above a c == above b d
  NoInterleave a b c d -> between c == between d
    where
      between x = above a x /= above b x
  Acyclic a b c -> not (circle a b c || circle c b a)
    where
      circle x y z = above x y && above y z && above z x

pair :: FaceId -> FaceId -> (FaceId, FaceId)
pair a b = (min a b, max a b)

-- | Two faces joined along an edge of the folded form.
data Hinge = Hinge
  { hingePanels :: !(Panel, Panel),
    hingeSegment :: !(V2, V2),
    hingeKind :: !HingeKind,
    -- | Whether the crease is a valley, when the file says either way.
    hingeValley :: !(Maybe Bool)
  }

-- | The two faces of a hinge, by id.
hingeFaces :: Hinge -> (FaceId, FaceId)
hingeFaces h = (panelId pf, panelId pg)
  where
    (pf, pg) = hingePanels h

-- | Which way the paper goes at a hinge, read from where the two faces lie
-- rather than from the recorded angle, for the same reason
-- "Senbazuru.Origami.Step" compares positions: the coordinates are the paper.
data HingeKind
  = -- | Both faces on one side of the line: folded flat back on itself.
    Taco
  | -- | One face each side: the paper continues flat across the line.
    Tortilla
  deriving stock (Eq, Show)

-- | Everything the solver needs, worked out from the geometry once.
data Analysis = Analysis
  { analysisFaceUp :: !(M.Map FaceId Bool),
    -- | Every pair of faces whose interiors overlap, in id order.
    analysisPairs :: ![(FaceId, FaceId)],
    analysisRules :: ![Rule]
  }

-- | The constraints a flat-folded frame places on its own layer order.
stackingRules :: Frame -> Either StackingError [Rule]
stackingRules fr = analysisRules <$> analyse fr

-- | A @faceOrders@ for a flat-folded frame that has none.
--
-- One entry per pair of faces whose interiors overlap, with the sign read
-- against the second face\'s normal as FOLD and "Senbazuru.Origami.Layers"
-- expect. Faces that do not overlap get no entry.
--
-- The first of however many valid orders the model has. Which one that is is
-- fixed by the face ids and reproducible, which the golden tests depend on;
-- 'solveStackingAs' is how to ask for another.
solveStacking :: Frame -> Either StackingError [FaceOrder]
solveStacking = solveStackingAs defaultBudget []

-- | The layer order a caller picked, out of the several a model may have.
--
-- @solveStackingAs budget choices fr@ takes one index per component that has a
-- choice in it, in the order 'stackingsChoices' lists them. A short list — and
-- the empty list 'solveStacking' passes — means index zero for the rest, so
-- @[]@ is the answer every version of senbazuru has given.
--
-- An index a component does not have is 'NoSuchStacking' rather than a
-- silently different picture.
-- | The layer order to draw or build a folded form by: the file\'s, or one
-- worked out, or nothing at all.
--
-- A file that supplies @faceOrders@ gets its own, checked but not second-guessed.
-- A file that does not gets one from 'solveStackingAs', which covers models
-- folded flat with convex faces; outside that it declines, having attempted
-- nothing, and there is no ordering to be had. An empty list is a real answer
-- — no two faces overlap — and is not the same as no answer.
--
-- A model the solver /tried/ and found impossible — no stacking of its layers
-- avoids the paper passing through itself — is refused rather than dropped.
-- These faces were going to be drawn or built, and the only account of how to
-- stack them is impossible; quietly producing something else instead is the
-- failure mode the renderers keep being written to avoid.
--
-- Here rather than in a renderer because two of them need it — the SVG of a
-- folded form and the 3D export both stand or fall by the same order — and a
-- policy copied into each would agree only by hand.
layerOrderFor :: Budget -> Frame -> Either FoldError (Maybe [FaceOrder])
layerOrderFor budget fr = do
  supplied <- frameFaceOrders fr
  if null supplied
    then case solveStackingAs budget [] fr of
      Right orders -> Right (Just orders)
      Left NotFlat {} -> Right Nothing
      Left NonConvexFace {} -> Right Nothing
      -- Unreachable, both of them: this asks for no particular order, so there
      -- is no index to be out of range and no component to be missing.
      -- Declining is the harmless answer.
      Left NoSuchStacking {} -> Right Nothing
      Left NoSuchComponent {} -> Right Nothing
      Left (StackingRefused err) -> Left err
    else Right (Just supplied)

solveStackingAs :: Budget -> [Int] -> Frame -> Either StackingError [FaceOrder]
solveStackingAs budget choices fr = do
  analysis <- analyse fr
  -- Only as many states of each component as the deepest index asks for. A
  -- model with more states than anyone can count is common -- one of
  -- Flat-Folder's has 10^83 of them -- and nobody picking the first needs the
  -- rest enumerated.
  --
  -- Saturating rather than @1 + maximum@, which overflows: an index near
  -- 'maxBound' wrapped to a negative want, every component then found nothing
  -- because the search stops when nothing more is wanted, and a perfectly
  -- stackable model was reported as impossible.
  space <- solutionSpace budget (foldl' upTo 1 choices) analysis
  -- An index for a component that is not there is a question about a different
  -- model, not a request to be ignored. Checked before the indices are matched
  -- up, because zipping a long list against a short one would drop it in
  -- silence.
  case drop (length (stackingsChoices space)) (zip [0 ..] choices) of
    ((i, _) : _) -> Left (NoSuchComponent i (length (stackingsChoices space)))
    [] -> Right ()
  above <- chosen space
  pure (ordersFrom analysis above)
  where
    upTo acc i
      | i >= maxBound - 1 = maxBound
      | otherwise = max acc (i + 1)

    -- The settled pairs go in first and every group's answer on top. Leaving
    -- them out is how the first version of this returned nothing at all for a
    -- model propagation had settled completely -- which is most of them.
    --
    -- Each group's answer already carries the settled pairs, since the search
    -- starts from them and never overwrites a key. They are put in again here
    -- for the case where there are no groups at all and nothing to carry them.
    chosen space =
      M.unions . (stackingsForced space :)
        <$> traverse pickOne (zip3 [0 ..] (stackingsChoices space) (choices <> repeat 0))
      where
        pickOne (i, choice, want) = case drop want (choiceStates choice) of
          (state : _) -> Right state
          -- Only when the search actually finished is the count a fact about
          -- the paper. Cut short by the budget, this component has at least
          -- what was found and possibly the one being asked for, and saying it
          -- has three orders when it has five would be the confident kind of
          -- wrong.
          []
            | choiceCapped choice -> Left (StackingRefused (GaveUpStacking budgetSpent))
            | otherwise -> Left (NoSuchStacking i want (length (choiceStates choice)))
        budgetSpent = budgetGuesses budget

-- | Every valid layer order a flat-folded frame has, described rather than
-- listed.
--
-- Enumerates each component to the budget, which is what @info@ reports and
-- what makes 'solveStackingAs'\'s indices meaningful.
stackingSpace :: Budget -> Frame -> Either StackingError Stackings
stackingSpace budget fr = analyse fr >>= solutionSpace budget maxBound

-- | The layer order as @faceOrders@, with the signs FOLD reads them by.
--
-- \"f is above g\" is \"f is on the +z side of g\". FOLD\'s sign is relative to
-- g\'s normal instead, which is +z when g lies top-up and -z when it lies
-- top-down. So the two agree exactly when g is top-up. The normal comes from
-- the same winding paintOrder will read it back with, which is what makes the
-- round trip cancel.
ordersFrom :: Analysis -> Above -> [FaceOrder]
ordersFrom analysis above =
  [ FaceOrder f g (if fOnTop == faceUp g then Above else Below)
    | ((f, g), fOnTop) <- M.toList above
  ]
  where
    faceUp g = M.findWithDefault True g (analysisFaceUp analysis)

-- | Geometry to constraints.
analyse :: Frame -> Either StackingError Analysis
analyse fr = do
  -- Everything about reading a flat-folded frame as polygons in a plane --
  -- including declining a model that is not one -- is
  -- "Senbazuru.Origami.Flat", because the visible-region finder needs exactly
  -- the same preparation and the two must not be able to disagree about it.
  sheet <- first fromFlat (flatSheet fr)
  valleys <- refused (creaseDirections fr (sheetCreases sheet))
  alongEdges <- refused (facesAlongEdges (sheetFaces sheet))
  let hair = sheetHair sheet
      speck = sheetSpeck sheet
      panels = sheetPanels sheet
      byId = M.fromList [(panelId p, p) | p <- panels]
      at = vertexAt sheet . VertexId
  hinges <-
    catMaybes
      <$> traverse
        (toHinge hair at byId valleys)
        [(k, (f, g)) | (k, [f, g]) <- M.toList alongEdges]
  let overlaps =
        [ (panelId a, panelId b)
          | (a : rest) <- tails panels,
            b <- rest,
            overlapArea (panelRing a) (panelRing b) > speck
        ]
      neighbours =
        M.fromListWith
          S.union
          (concat [[(a, S.singleton b), (b, S.singleton a)] | (a, b) <- overlaps])
      neighboursOf f = M.findWithDefault S.empty f neighbours
      ringOf f = maybe [] panelRing (M.lookup f byId)

      -- Every triple of faces that share a patch of paper: for each overlapping
      -- pair, the faces overlapping both of them. Enumerating all triples of
      -- faces instead is cubic in the face count before a single polygon is
      -- clipped, and a real model has hundreds of faces.
      commonPatches =
        [ Acyclic a b c
          | (a, b) <- overlaps,
            c <- S.toList (S.intersection (neighboursOf a) (neighboursOf b)),
            c > b,
            overlapArea (ringOf c) (clipConvex (ringOf a) (ringOf b)) > speck
        ]

      creaseRules = concatMap (creaseRule hair) hinges
      crossingRules =
        [ crossingRule h t
          | h <- hinges,
            let (a, b) = hingeFaces h,
            t <- panels,
            panelId t `notElem` [a, b],
            runsAcross hair (panelRing t) (hingeSegment h)
        ]
      collinearRules =
        concat [collinearRule hair h1 h2 | (h1 : rest) <- tails hinges, h2 <- rest]

      rules = creaseRules <> crossingRules <> collinearRules <> commonPatches

      -- The variables: every pair the geometry found overlapping, and every
      -- pair a rule mentions. A rule's pairs overlap by construction -- a
      -- tortilla across a taco's line shares paper with both its faces -- but
      -- can slip under the area threshold when a face is a sliver, and
      -- dropping the rule for that would drop a fact about the paper.
      tacoPairs =
        [pair a b | h <- hinges, hingeKind h == Taco, let (a, b) = hingeFaces h]
      pairs = S.toAscList (S.fromList (overlaps <> tacoPairs <> concatMap rulePairs rules))
  pure
    Analysis
      { analysisFaceUp = M.fromList [(panelId p, panelFaceUp p) | p <- panels],
        analysisPairs = pairs,
        analysisRules = rules
      }
  where
    refused :: Either FoldError a -> Either StackingError a
    refused = first StackingRefused

-- | A reason a frame is not a flat sheet of convex faces, as a reason no
-- ordering was produced.
--
-- The two types stay separate because they answer different questions: a
-- 'FlatError' is about the model, and 'StackingError' is about this module's
-- attempt on it, which can also fail for a reason — 'Unstackable' — that has
-- nothing to do with lying in a plane.
fromFlat :: FlatError -> StackingError
fromFlat = \case
  PaperInTheAir dz -> NotFlat dz
  ConcaveFace f -> NonConvexFace f
  FlatRefused err -> StackingRefused err

-- | The hinge along one edge shared by two faces, if the edge has any length
-- in the folded form.
--
-- This is where the windings are checked against each other. The two faces of
-- a taco are the same sheet folded over, so one lies top-up and the other
-- top-down; the two faces of a tortilla are the same sheet continuing, so they
-- lie the same way. A file whose windings say otherwise is refused, because
-- every sign in the answer would be read against them.
toHinge ::
  Double ->
  (Int -> V2) ->
  M.Map FaceId Panel ->
  M.Map EdgeKey (Maybe Bool) ->
  (EdgeKey, (FaceId, FaceId)) ->
  Either StackingError (Maybe Hinge)
toHinge hair at byId valleys (key@(a, b), (f, g)) = case (M.lookup f byId, M.lookup g byId) of
  (Just pf, Just pg)
    -- Two corners of the pattern that land on one point of the folded form
    -- are not an edge of it, and there is no line for anything to be a side
    -- of. Nothing is said about them.
    | norm (q ^-^ p) <= hair -> Right Nothing
    | kind == Taco && panelFaceUp pf == panelFaceUp pg -> clash
    | kind == Tortilla && panelFaceUp pf /= panelFaceUp pg -> clash
    | otherwise ->
        Right
          ( Just
              Hinge
                { hingePanels = (pf, pg),
                  hingeSegment = (p, q),
                  hingeKind = kind,
                  hingeValley = M.findWithDefault Nothing key valleys
                }
          )
    where
      p = at a
      q = at b
      kind
        | leftOf (p, q) pf == leftOf (p, q) pg = Taco
        | otherwise = Tortilla
      clash = Left (StackingRefused (WindingClash f g))
  -- Impossible: the ids came from these panels' faces. Saying nothing rather
  -- than something invented.
  _ -> Right Nothing

-- | Which side of a directed line a face lies on.
--
-- Only meaningful for a face with an edge along that line, which is the only
-- way it is used: every corner is then on the line or on one side, so the mean
-- of the corners is strictly on that side.
leftOf :: (V2, V2) -> Panel -> Bool
leftOf (p, q) panel = cross2 (q ^-^ p) (centroid (panelRing panel) ^-^ p) > 0

-- | The area two faces have in common.
overlapArea :: [V2] -> [V2] -> Double
overlapArea a b = abs (signedArea (clipConvex a b))

-- | Does a segment pass through the interior of a face, rather than along its
-- edge or past a corner?
--
-- Positive length inside, and a midpoint clear of every edge: a segment lying
-- along an edge clips to itself but its midpoint sits on the boundary, and a
-- segment through a corner clips to a point.
runsAcross :: Double -> [V2] -> (V2, V2) -> Bool
runsAcross hair ring seg = case clipSegment ring seg of
  Just (u, v) -> norm (v ^-^ u) > hair && strictlyInside hair ring (0.5 *^ (u ^+^ v))
  Nothing -> False

-- | The rule a crease imposes by itself: its assignment, for a taco.
--
-- A tortilla's faces do not overlap, so its assignment orders nothing. A taco
-- whose direction the file does not give is left to the other rules.
creaseRule :: Double -> Hinge -> [Rule]
creaseRule _ h = case (hingeKind h, hingeValley h) of
  (Taco, Just valley) -> [Fixed down up valley]
  _ -> []
  where
    (pf, pg) = hingePanels h
    -- A valley brings the two top sides together, so the face lying top-down
    -- is the one on top. A mountain brings the undersides together and it is
    -- underneath. Either way the face lying top-up is the reference.
    (down, up)
      | panelFaceUp pf = (panelId pg, panelId pf)
      | otherwise = (panelId pf, panelId pg)

-- | The rule a hinge imposes on a face whose interior its line runs through.
--
-- For a taco this is taco-tortilla: the face cannot be inside the fold. For a
-- tortilla it is tortilla-tortilla with a twist worth noticing — the crossing
-- face is itself a tortilla across the same line, whose two halves happen to
-- be one face, so the rule is 'SameOrder' with that face on both sides. The
-- two constructors say the same thing about @t@; writing the tortilla case
-- this way names the shape of the paper rather than just the formula, and it
-- is how Flat-Folder files it, which lets its counts be compared with ours.
crossingRule :: Hinge -> Panel -> Rule
crossingRule h t = case hingeKind h of
  Taco -> NotBetween (panelId t) a b
  Tortilla -> SameOrder a (panelId t) b (panelId t)
  where
    (a, b) = hingeFaces h

-- | The rules two hinges on one line impose on each other.
collinearRule :: Double -> Hinge -> Hinge -> [Rule]
collinearRule hair h1 h2 = case collinearOverlap hair (hingeSegment h1) (hingeSegment h2) of
  Nothing -> []
  Just shared
    -- A face with two edges on one line is either degenerate or has a corner in
    -- the middle of a straight side, and in the second case the two edges only
    -- touch. Either way there is nothing to say.
    | any (`elem` [c, d]) [a, b] -> []
    | otherwise -> case (hingeKind h1, hingeKind h2) of
        (Taco, Taco)
          | side pa == side pc -> [NoInterleave a b c d]
          -- Folded on the same line but to opposite sides: they do not overlap.
          | otherwise -> []
        -- The tortilla's face on the taco's side runs across the taco's fold.
        (Taco, Tortilla) -> [NotBetween (panelId (besides pa (pc, pd))) a b]
        (Tortilla, Taco) -> [NotBetween (panelId (besides pc (pa, pb))) c d]
        -- Pair each face with the one across from it on the same side.
        (Tortilla, Tortilla) -> [SameOrder a (panelId (besides pa (pc, pd))) b (panelId (besides pb (pc, pd)))]
    where
      (pa, pb) = hingePanels h1
      (pc, pd) = hingePanels h2
      (a, b) = hingeFaces h1
      (c, d) = hingeFaces h2
      -- All four judged against the one shared segment, so that the two
      -- hinges being written in opposite directions cannot matter.
      side = leftOf shared
      besides x (y, z)
        | side y == side x = y
        | otherwise = z

-- | Which way each crease folds, by the edge it is: valley, mountain, or
-- unknown.
--
-- From the fold angle when the frame records one that is not zero, else from
-- the assignment. The angle is preferred because it is the state of a folded
-- frame; the assignment is the fallback because it names a direction without
-- an amount, which is all this needs. A file whose @edges_foldAngle@ is the
-- wrong length is refused, as "Senbazuru.Origami.Folding" refuses it: a wrong
-- direction here mirrors the whole stack in silence.
creaseDirections :: Frame -> [Crease] -> Either FoldError (M.Map EdgeKey (Maybe Bool))
creaseDirections fr creases = do
  angles <- case edgesFoldAngle fr of
    [] -> Right (map (const Nothing) creases)
    as
      | length as == length creases -> Right (map Just as)
      | otherwise ->
          Left (ArrayLengthMismatch "edges_vertices" (length creases) "edges_foldAngle" (length as))
  pure
    ( M.fromListWith
        (\_new old -> old)
        [(edgeKey (creaseFrom c) (creaseTo c), direction c angle) | (c, angle) <- zip creases angles]
    )
  where
    direction c = \case
      Just d
        | d > 0 -> Just True
        | d < 0 -> Just False
      _ -> case creaseAssignment c of
        Valley -> Just True
        Mountain -> Just False
        _ -> Nothing

-- | Which face of each pair is on top, keyed by @(lower id, higher id)@ and
-- answering \"is the lower one above?\".
type Above = M.Map (FaceId, FaceId) Bool

-- | Is @f@ above @g@, given a handful of pairs being tried out over everything
-- already decided?
--
-- Only asked once every pair a rule names is decided, so the default is never
-- read; it is there to keep the lookup total.
--
-- Two maps rather than one, and that is the whole reason this exists. The
-- propagation tries a few pairs at a time against everything settled so far,
-- and the obvious way to ask is to union them — which is correct, since union
-- is left-biased and the trial wins, and which rebuilds the settled map every
-- time. That map holds one entry per overlapping pair, so on a 161-layer
-- accordion it is 12,880 entries copied to consult three keys, and it was a
-- third of the allocation in a whole run. Looking in the small one first and
-- falling through costs two lookups in the worst case.
aboveWith :: Above -> Above -> FaceId -> FaceId -> Bool
aboveWith way known f g
  | f < g = look (f, g)
  | otherwise = not (look (g, f))
  where
    look k = case M.lookup k way of
      Just v -> v
      Nothing -> M.findWithDefault False k known

-- | Every valid layer order a model has, as a product rather than a list.
--
-- A model with several valid orders usually has a great many, because they
-- multiply: Flat-Folder\'s corpus contains one with more states than there are
-- atoms in the observable universe. Listing them is out of the question and
-- unnecessary, because the choices are independent. What is listed instead is
-- the choices themselves.
data Stackings = Stackings
  { -- | The pairs propagation settled without a guess. Every valid order of
    -- this model agrees about all of them.
    stackingsForced :: !Above,
    -- | The groups of pairs that are still open, each with the assignments it
    -- admits. A group cannot affect another: no rule joins them, so nothing
    -- decided in one can propagate into the next, which is the whole reason
    -- they can be solved and counted separately.
    stackingsChoices :: ![Choice]
  }
  deriving stock (Eq, Show)

-- | One group of pairs and the ways it can be filled in.
data Choice = Choice
  { -- | The pairs of faces this group is a choice about. Every valid order of
    -- the model agrees about every pair outside it.
    choicePairs :: ![(FaceId, FaceId)],
    -- | The assignments, in the order the search finds them, which is the order
    -- 'solveStackingAs' indexes. Never empty: a group with no assignment at all
    -- makes the whole model unstackable.
    choiceStates :: ![Above],
    -- | Whether the budget ran out before the search had found them all, so
    -- that there are at least this many rather than exactly this many.
    choiceCapped :: !Bool,
    -- | How many guesses finding them cost. Recorded because it is the one
    -- number that says whether propagation is doing its job: a change that
    -- weakened it would show up here as a bigger count long before it showed
    -- up anywhere else as a slower run.
    choiceGuesses :: !Int
  }
  deriving stock (Eq, Show)

-- | How many components the model has, counting the settled pairs as one.
--
-- The settled pairs are one component whether there are any of them or not,
-- which looks like an off-by-one and is a deliberate match: it is how
-- Flat-Folder counts, and counting the same way is what lets its published
-- figures be compared with ours model by model. Its file records the crane as
-- two components with @|1|5|@ assignments — one settled group admitting a
-- single answer, and one open group admitting five.
componentCount :: Stackings -> Int
componentCount space = 1 + length (stackingsChoices space)

-- | How many valid layer orders the model has: the product over the components.
--
-- 'Integer' because it does not fit in anything smaller. Paired with whether a
-- budget cut any component short, in which case the model has at least this
-- many rather than exactly this many.
stateCount :: Stackings -> (Integer, Bool)
stateCount space =
  ( product [toInteger (length (choiceStates c)) | c <- stackingsChoices space],
    any choiceCapped (stackingsChoices space)
  )

-- | Propagate, split, and search each part on its own.
--
-- Propagation first: a rule is checked by trying every way of filling in its
-- undecided pairs — there are at most four, so at most sixteen — and any pair
-- that comes out the same in every way that works is decided. A rule with no
-- way that works is the contradiction. Deciding a pair re-checks the rules that
-- mention it, and so on until nothing changes.
--
-- Then the pairs propagation could not settle are split into groups: two pairs
-- are joined when some rule still names both of them, and a group is what that
-- joining connects. Nothing decided in one group can reach another — every rule
-- lies wholly inside one — so each is searched separately, and the model\'s
-- valid orders are every combination of theirs. That is the difference between
-- a cost that adds up over the groups and one that multiplies, and it is why
-- the crane\'s 87 open pairs are not 2^87 of anything.
--
-- Within a group the search is depth first over the pairs in id order, trying
-- \"lower id on top\" before the other way and propagating after each guess.
-- Taking the first answer of every group therefore gives what every version of
-- this module has given, because the interleaving the old whole-model search
-- did between groups never affected any of them.
solutionSpace :: Budget -> Int -> Analysis -> Either StackingError Stackings
solutionSpace (Budget budget) wanted analysis = do
  settled <- refused (propagate M.empty (IM.keys byIndex))
  let open = [p | p <- analysisPairs analysis, M.notMember p settled]
  choices <- traverse (search settled) (components settled open)
  pure Stackings {stackingsForced = settled, stackingsChoices = choices}
  where
    rules = analysisRules analysis
    byIndex = IM.fromList (zip [0 ..] rules)
    touching = M.fromListWith (<>) [(p, [i]) | (i, r) <- IM.toList byIndex, p <- rulePairs r]
    rulesOn p = M.findWithDefault [] p touching

    refused = first (StackingRefused . Unstackable . ruleFaces)

    -- The groups, in the order their lowest pair appears, so that an index into
    -- them means the same thing on every run.
    components settled = go S.empty
      where
        joined =
          M.fromListWith
            (<>)
            [ (p, [q])
              | r <- rules,
                let stillOpen = [x | x <- rulePairs r, M.notMember x settled],
                p <- stillOpen,
                q <- stillOpen,
                p /= q
            ]
        go _ [] = []
        go seen (p : rest)
          | p `S.member` seen = go seen rest
          | otherwise =
              let group = reach S.empty [p]
               in S.toAscList group : go (S.union seen group) rest
        reach seen [] = seen
        reach seen (p : rest)
          | p `S.member` seen = reach seen rest
          | otherwise = reach (S.insert p seen) (M.findWithDefault [] p joined <> rest)

    -- A group with no assignment at all cannot be filled in, and neither can
    -- the model. Named by its faces rather than by one rule: the contradiction
    -- was reached down some branch of the search, and no single rule is to
    -- blame for it the way one is when propagation alone finds it.
    search settled group = case explore wanted budget group settled of
      ([], left)
        -- Nothing found and nothing left to spend: the search was cut off, so
        -- whether this part has an order is not known either way. Saying it has
        -- none would be the one answer that is certainly wrong.
        | left <= 0 -> Left (StackingRefused (GaveUpStacking budget))
      ([], _) -> Left (StackingRefused (Unstackable (nub (concatMap both group))))
      (states, left) ->
        Right
          Choice
            { choicePairs = group,
              choiceStates = states,
              choiceCapped = left <= 0 && length states < wanted,
              choiceGuesses = budget - left
            }
      where
        both (a, b) = [a, b]

    -- Depth first, at most @want@ answers, at most @spend@ guesses. Returns
    -- what it found and what is left of the budget, so that the two branches of
    -- a guess share one allowance rather than each getting a fresh one.
    explore want spend pairs known
      | want <= 0 = ([], spend)
      | otherwise = case dropWhile (`M.member` known) pairs of
          [] -> ([known], spend)
          (p : rest) ->
            let (yes, afterYes) = guess p True rest spend want known
                (no, afterNo) = guess p False rest afterYes (want - length yes) known
             in (yes <> no, afterNo)

    guess p v rest spend want known
      | want <= 0 = ([], spend)
      | spend <= 0 = ([], 0)
      | otherwise = case propagate (M.insert p v known) (rulesOn p) of
          Left _ -> ([], spend - 1)
          Right known' -> explore want (spend - 1) rest known'

    propagate known [] = Right known
    propagate known (i : queue) = case IM.lookup i byIndex of
      -- The queue only ever holds indices of byIndex, so this is unreachable;
      -- skipping is the harmless answer.
      Nothing -> propagate known queue
      Just rule ->
        let open = [p | p <- rulePairs rule, M.notMember p known]
            ways = [M.fromList choice | choice <- sequence [[(p, True), (p, False)] | p <- open]]
            -- Two maps, not their union: see 'aboveWith'.
            fitting = [way | way <- ways, ruleHolds (aboveWith way known) rule]
            forced =
              [ (p, v)
                | p <- open,
                  (v : rest) <- [[M.findWithDefault False p way | way <- fitting]],
                  all (== v) rest
              ]
         in if null fitting
              then Left rule
              else
                propagate
                  (foldr (uncurry M.insert) known forced)
                  (concatMap (rulesOn . fst) forced <> queue)
