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
--    across the line, and the fold would have to pass through it. The same
--    holds for a face that runs across a tortilla's line, for the same reason.
--
-- 3. __Taco-taco__ ('NoInterleave'). Two tacos folded on the same line, on the
--    same side, must nest or stay apart. If one face of a taco is between the
--    other taco's faces, so is its partner.
--
-- 4. __Tortilla-tortilla__ ('SameOrder'). Two sheets continuing flat across
--    the same line cannot cross it in opposite orders.
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
module Senbazuru.Origami.Stacking
  ( solveStacking,
    StackingError (..),
    renderStackingError,

    -- * The constraints
    Rule (..),
    stackingRules,
  )
where

import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (tails)
import Data.Map.Strict qualified as M
import Data.Maybe (catMaybes)
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import Numeric (showGFloat)
import Senbazuru.Fold.Query
  ( Crease (..),
    EdgeKey,
    Face (..),
    FoldError (..),
    edgeKey,
    facesAlongEdges,
    frameCreases,
    frameFaces,
    frameVertices,
    renderFoldError,
  )
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FaceOrder (..),
    Frame (..),
    Stacking (..),
  )
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, spanAlong, zSpan)
import Senbazuru.Geometry.VectorSpace

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
  | -- | The frame is unsound, or its layers cannot be stacked at all.
    StackingRefused !FoldError
  deriving stock (Eq, Show)

-- | A human-readable rendering of a 'StackingError'.
renderStackingError :: StackingError -> Text
renderStackingError = \case
  NotFlat dz ->
    "the model spans "
      <> T.pack (showGFloat (Just 6) dz "")
      <> " in z; working out which layer is on top is only implemented for"
      <> " models folded flat"
  NonConvexFace (FaceId f) ->
    "face "
      <> T.pack (show f)
      <> " is not convex, and the test for whether two faces overlap is only"
      <> " right for convex ones"
  StackingRefused err -> renderFoldError err

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
    -- line, @a@ and @c@ on the same side of it.
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

-- | Every face a rule mentions, for naming the culprits.
ruleFaces :: Rule -> [FaceId]
ruleFaces = \case
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

-- | One face of the folded model as it lies in the plane.
data Panel = Panel
  { panelId :: !FaceId,
    -- | The corners, anticlockwise whichever way the file listed them, so the
    -- clipping below can assume a direction.
    panelRing :: ![V2],
    -- | Whether the file's winding runs anticlockwise as the face lies here —
    -- that is, whether the top side of the paper faces @+z@ at this face.
    panelFaceUp :: !Bool
  }

-- | Two faces joined along an edge of the folded form.
data Hinge = Hinge
  { hingePanels :: !(Panel, Panel),
    hingeSegment :: !(V2, V2),
    hingeKind :: !HingeKind,
    -- | Whether the crease is a valley, when the file says either way.
    hingeValley :: !(Maybe Bool)
  }

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
-- against the second face's normal as FOLD and "Senbazuru.Origami.Layers"
-- expect. Faces that do not overlap get no entry.
solveStacking :: Frame -> Either StackingError [FaceOrder]
solveStacking fr = do
  analysis <- analyse fr
  above <-
    first
      (StackingRefused . Unstackable . ruleFaces)
      (solve (analysisPairs analysis) (analysisRules analysis))
  -- "f is above g" is "f is on the +z side of g". FOLD's sign is relative to
  -- g's normal instead, which is +z when g lies top-up and -z when it lies
  -- top-down. So the two agree exactly when g is top-up. The normal comes from
  -- the same winding paintOrder will read it back with, which is what makes
  -- the round trip cancel.
  let faceUp g = M.findWithDefault True g (analysisFaceUp analysis)
  pure
    [ FaceOrder f g (if fOnTop == faceUp g then Above else Below)
      | ((f, g), fOnTop) <- M.toList above
    ]

-- | Geometry to constraints.
analyse :: Frame -> Either StackingError Analysis
analyse fr = do
  verts <- refused (frameVertices fr)
  -- Checked before anything looks at a face, so a folded form with paper in
  -- the air is declined on its vertices alone and a corrupt face in it stays
  -- the renderer's business, as it was before this module existed.
  if hasRelief verts then Left (NotFlat (zSpan verts)) else Right ()
  faces <- refused (frameFaces fr)
  creases <- refused (frameCreases fr)
  valleys <- refused (creaseDirections fr creases)
  alongEdges <- refused (facesAlongEdges faces)
  let -- Both tolerances are relative to the size of the sheet, as every other
      -- one in this project is. The area one is a length tolerance squared:
      -- rounding leaves slivers a hair wide along every shared edge, and their
      -- area is that hair times the length of the sheet, so the threshold sits
      -- well above them and well below any face a person would draw.
      scale = max 1 (max (spanAlong v3x verts) (spanAlong v3y verts))
      hair = 1e-9 * scale
      speck = hair * scale
      flatten (V3 x y _) = V2 x y
      positions = IM.fromList (zip [0 ..] (map flatten verts))
  panels <- traverse (toPanel speck flatten) faces
  let byId = M.fromList [(panelId p, p) | p <- panels]
      -- Total in practice: every vertex id here came out of a face that
      -- frameFaces checked against these very vertices.
      at v = IM.findWithDefault (V2 0 0) v positions
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
        [ NotBetween (panelId t) (panelId a) (panelId b)
          | h <- hinges,
            let (a, b) = hingePanels h,
            t <- panels,
            panelId t /= panelId a,
            panelId t /= panelId b,
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
        [pair (panelId a) (panelId b) | h <- hinges, hingeKind h == Taco, let (a, b) = hingePanels h]
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

-- | A face as it lies in the plane, or why it cannot be one.
--
-- Area comes first: a face with none has no winding to read, and refusing it
-- is the file's fault ('FaceWithoutNormal'). Convexity comes second and is
-- declined rather than refused, because a concave face is not wrong, merely
-- outside what the overlap test can answer.
toPanel :: Double -> (V3 -> V2) -> Face -> Either StackingError Panel
toPanel speck flatten f
  | abs area <= speck = Left (StackingRefused (FaceWithoutNormal (faceId f)))
  | not (isConvex speck ring) = Left (NonConvexFace (faceId f))
  | otherwise =
      Right
        Panel
          { panelId = faceId f,
            panelRing = if area > 0 then ring else reverse ring,
            panelFaceUp = area > 0
          }
  where
    ring = map flatten (faceCorners f)
    area = signedArea ring

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
      (a, b) = (panelId pa, panelId pb)
      (c, d) = (panelId pc, panelId pd)
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

-- | Is @f@ above @g@, in a partial answer?
--
-- Only asked once every pair a rule names is decided, so the default is never
-- read; it is there to keep the lookup total.
aboveIn :: Above -> FaceId -> FaceId -> Bool
aboveIn known f g
  | f < g = M.findWithDefault False (f, g) known
  | otherwise = not (M.findWithDefault False (g, f) known)

-- | Find an assignment to every pair that satisfies every rule, or the rule
-- that could not be satisfied.
--
-- Propagation first: a rule is checked by trying every way of filling in its
-- undecided pairs — there are at most four, so at most sixteen — and any pair
-- that comes out the same in every way that works is decided. A rule with no
-- way that works is the contradiction. Deciding a pair re-checks the rules
-- that mention it, and so on until nothing changes.
--
-- Then search: the lowest undecided pair is set to \"lower id on top\" and
-- propagation runs again; if that ends in contradiction the pair is set the
-- other way instead. Trying the same answer first for every free pair means
-- pairs no rule touches come out in id order, which never puts a circle in the
-- answer by itself.
solve :: [(FaceId, FaceId)] -> [Rule] -> Either Rule Above
solve pairs rules = propagate M.empty (IM.keys byIndex) >>= search pairs
  where
    byIndex = IM.fromList (zip [0 ..] rules)
    touching = M.fromListWith (<>) [(p, [i]) | (i, r) <- IM.toList byIndex, p <- rulePairs r]
    rulesOn p = M.findWithDefault [] p touching

    search pending known = case dropWhile (`M.member` known) pending of
      [] -> Right known
      (p : rest) -> case decide p True rest known of
        Right done -> Right done
        Left _ -> decide p False rest known

    decide p v rest known = propagate (M.insert p v known) (rulesOn p) >>= search rest

    propagate known [] = Right known
    propagate known (i : queue) = case IM.lookup i byIndex of
      -- The queue only ever holds indices of byIndex, so this is unreachable;
      -- skipping is the harmless answer.
      Nothing -> propagate known queue
      Just rule ->
        let open = [p | p <- rulePairs rule, M.notMember p known]
            ways = [M.fromList choice | choice <- sequence [[(p, True), (p, False)] | p <- open]]
            fitting = [way | way <- ways, ruleHolds (aboveIn (M.union way known)) rule]
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
