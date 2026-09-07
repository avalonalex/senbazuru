-- |
-- Module      : Senbazuru.Origami.Flat
-- Description : A model folded flat, read as convex polygons in one plane.
--
-- A __flat-folded__ model is one whose paper has all come back into a single
-- plane — the traditional crane, a paper aeroplane pressed shut, a square
-- folded into quarters. It is the case two separate pieces of senbazuru care
-- about, for the same reason: once every face lies in one plane, \"which layer
-- is on top\" is a question about polygons rather than about space.
--
-- "Senbazuru.Origami.Stacking" asks it to /solve/ for a layer order.
-- "Senbazuru.Origami.Visible" asks it to work out what can be seen. Both need
-- the same preparation — is the model flat at all, what are its faces as
-- polygons in that plane, which way up does each lie, and how small is small —
-- and this module is that preparation, in one copy.
--
-- It is here rather than next to either caller for the reason
-- 'Senbazuru.Geometry.V3.hasRelief' is where it is: two copies of a test like
-- \"is this flat\" agree only by hand, and the day they stop agreeing one
-- module refuses a model the other has already drawn.
--
-- == The two limits
--
-- 'flatSheet' declines two kinds of model, and neither is a fault in the file.
--
-- A model with paper still in the air ('PaperInTheAir') is a perfectly good
-- folded form; it is just not one whose layers can be reasoned about in a
-- plane. A face that is not convex ('ConcaveFace') is likewise fine paper —
-- but "Senbazuru.Geometry.Polygon" clips convex polygons only, so every
-- question either caller wants to ask about it would be answered wrongly
-- rather than refused. Kawasaki's theorem makes the faces of a flat-foldable
-- pattern convex whenever the sheet is, so this refuses very little.
--
-- Only the third constructor is the file's fault, and it carries the
-- 'FoldError' that says what is wrong with it.
--
-- == The winding is read, not recomputed
--
-- 'panelFaceUp' is the whole reason a 'Panel' is not just a list of points.
-- FOLD defines a face's normal by the order of its @faces_vertices@, and in a
-- folded form that order is doing real work: it says which side of the sheet
-- is looking at @+z@. Turning a face over reverses it, so reading the winding
-- back is how anything downstream tells a face lying top-up from one lying
-- top-down — and it is what @faceOrders@'s signs were written against. See
-- "Senbazuru.Origami.Layers" for why recomputing it would turn a model inside
-- out.
--
-- The ring in 'panelRing' /is/ turned anticlockwise, so that the clipping
-- routines can assume a direction, and 'panelFaceUp' is what that cost.
module Senbazuru.Origami.Flat
  ( -- * A flat-folded model
    Sheet (..),
    Panel (..),
    flatSheet,
    vertexAt,

    -- * Why it is not one
    FlatError (..),
  )
where

import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Query
  ( Crease (..),
    Face (..),
    FoldError (..),
    frameCreases,
    frameFaces,
    frameVertices,
  )
import Senbazuru.Fold.Types (FaceId (..), Frame (..), VertexId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (isConvex, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), hasRelief, spanAlong, zSpan)

-- | One face of a flat-folded model as it lies in the plane.
data Panel = Panel
  { panelId :: !FaceId,
    -- | The corners, anticlockwise whichever way the file listed them, so the
    -- clipping routines can assume a direction.
    panelRing :: ![V2],
    -- | Whether the file's winding runs anticlockwise as the face lies here —
    -- that is, whether the top side of the paper faces @+z@ at this face.
    panelFaceUp :: !Bool
  }
  deriving stock (Eq, Show)

-- | A whole model folded flat, with the yardsticks for judging it.
--
-- 'sheetFaces' and 'sheetPanels' are the same faces twice over, and both are
-- kept because they answer different questions: a 'Panel' is the geometry, and
-- a 'Face' still has its vertex /ids/, which is what a caller reasoning about
-- the graph — which faces meet along which edge — needs and cannot recover
-- from coordinates. They are in the same order, one per face.
data Sheet = Sheet
  { sheetFaces :: ![Face],
    sheetPanels :: ![Panel],
    -- | Every crease of the frame, resolved once. Both callers want them and
    -- neither wants to be the one that discovers a malformed @edges_@ array.
    sheetCreases :: ![Crease],
    -- | Every vertex of the frame flattened into the plane, by id. Read it
    -- with 'vertexAt' rather than directly, so that the answer for an id that
    -- is not there is decided in one place.
    sheetPositions :: !(IM.IntMap V2),
    -- | The @z@ the model lies at: what to put back when a point worked out in
    -- the plane has to become a point in space again.
    sheetPlane :: !Double,
    -- | A length below which two points are the same point. Relative to the
    -- size of the sheet, as every tolerance in this project is: rounding
    -- leaves gaps a hair wide wherever two folded edges should coincide.
    sheetHair :: !Double,
    -- | An area below which a polygon is nothing. The length tolerance
    -- squared — or rather times the size of the sheet, since the slivers this
    -- has to swallow are a hair wide and as long as the paper.
    sheetSpeck :: !Double
  }
  deriving stock (Eq, Show)

-- | Why a frame is not a flat-folded model of convex faces.
data FlatError
  = -- | The paper has not all come back into one plane. Carries how far the
    -- model spans in @z@.
    PaperInTheAir !Double
  | -- | A face is not convex, and the clipping this is preparation for is only
    -- right for convex polygons.
    ConcaveFace !FaceId
  | -- | The frame itself is unsound, in a way that has nothing to do with
    -- being flat.
    FlatRefused !FoldError
  deriving stock (Eq, Show)

-- | The plain statement of the fact, with nothing about what it stops.
--
-- Nothing prints this today: every caller of 'flatSheet' flattens a
-- 'FlatError' into its own error type first, because the useful message says
-- what the model being unflat /prevented/ — working out which layer is on top,
-- or reading a line drawn on the model — and this module does not know which
-- of those was being attempted. So each caller has its own @fromFlat@, and the
-- clause about what it was doing is the only part that differs between them.
--
-- The instance exists anyway, and is the stem both of those messages are
-- variations of. An error type that is only ever taken apart is one @Left@
-- away from being printed, and a type with no words of its own is the one that
-- gets printed with @show@.
instance Explain FlatError where
  explain = \case
    PaperInTheAir dz ->
      "the model spans " <> num dz <> " in z, so it is not folded flat"
    ConcaveFace (FaceId f) ->
      "face " <> tshow f <> " is not convex"
    FlatRefused err -> explain err

-- | Read a frame as a flat-folded model, or say why it is not one.
--
-- The order the checks run in is deliberate twice over.
--
-- The flatness test comes before anything looks at a face: a folded form with
-- paper in the air is declined on its vertices alone, so a corrupt face in one
-- stays whoever-was-going-to-draw-it's business rather than becoming this
-- module's.
--
-- Everything that can find the /frame/ malformed then runs before the panels
-- are built. That is because a 'FlatRefused' and a 'ConcaveFace' are answers of
-- different kinds — the first says the file is wrong, the second says this
-- module does not cover the model — and a caller that draws the declined case
-- anyway would otherwise never hear about the first. It has to be this way
-- round and not the other: a concave face is not a reason to stop reading, and
-- a broken array is.
flatSheet :: Frame -> Either FlatError Sheet
flatSheet fr = do
  verts <- refused (frameVertices fr)
  if hasRelief verts then Left (PaperInTheAir (zSpan verts)) else Right ()
  faces <- refused (frameFaces fr)
  creases <- refused (frameCreases fr)
  -- Measured across the plane rather than in all three directions, because the
  -- model is flat and its z extent is rounding noise. Bounded below by 1 so
  -- that a model smaller than a unit does not shrink its own tolerance to
  -- nothing.
  let scale = max 1 (max (spanAlong v3x verts) (spanAlong v3y verts))
      hair = 1e-9 * scale
      speck = hair * scale
  panels <- traverse (toPanel speck) faces
  pure
    Sheet
      { sheetFaces = faces,
        sheetPanels = panels,
        sheetCreases = creases,
        sheetPositions = IM.fromList (zip [0 ..] (map flatten verts)),
        sheetPlane = plane verts,
        sheetHair = hair,
        sheetSpeck = speck
      }
  where
    refused :: Either FoldError a -> Either FlatError a
    refused = first FlatRefused

-- | Where a vertex of the frame lies in the plane.
--
-- Total, and the fallback is never reached in practice: every id a caller has
-- came out of a face or an edge that 'frameFaces' or 'frameCreases' already
-- checked against these very vertices. It is here so that both callers cannot
-- disagree about what an impossible id means.
vertexAt :: Sheet -> VertexId -> V2
vertexAt sheet v = IM.findWithDefault (V2 0 0) (unVertexId v) (sheetPositions sheet)

-- | The plane the model lies in: the middle of whatever @z@ range it spans.
--
-- The middle rather than the first vertex's @z@, so that rounding noise in one
-- corner cannot move the whole plane. A frame with no vertices has no plane,
-- and zero is as good an answer as any — 'flatSheet' has already established
-- there is nothing to draw.
plane :: [V3] -> Double
plane verts = case map v3z verts of
  [] -> 0
  zs -> 0.5 * (minimum zs + maximum zs)

-- | Drop @z@. Only sound once the model is known flat, which is why this is
-- not exported.
flatten :: V3 -> V2
flatten (V3 x y _) = V2 x y

-- | A face as it lies in the plane, or why it cannot be one.
--
-- Area comes first: a face with none has no winding to read, and refusing it
-- is the file's fault ('FaceWithoutNormal'). Convexity comes second and is
-- declined rather than refused, because a concave face is not wrong, merely
-- outside what the clipping can answer.
toPanel :: Double -> Face -> Either FlatError Panel
toPanel speck f
  | abs area <= speck = Left (FlatRefused (FaceWithoutNormal (faceId f)))
  | not (isConvex speck ring) = Left (ConcaveFace (faceId f))
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
