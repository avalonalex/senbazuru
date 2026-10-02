-- | Lower one wing of the traditional crane in examples/crane.fold.
-- The fixture finishes with both wings lying flat against the body. Add a
-- crease across one wing along a folded line y = h, then turn the wing's
-- material faces on the tip's side of it together through 90 degrees. A
-- material face is a region between creases; coincident faces remain
-- different pieces of paper. See docs/glossary.md for material coordinates,
-- fold angles and layer order.
--
-- The fixture lands upside down, negative y up (README, "Why the crane is
-- upside down"): the wing's tip is at y = 0 and the body's underside at
-- y = 1/2. The studies have always used h = 1/4 ('studyHinge'), a little
-- outboard of where the wing leaves the body; 'buildCraneWingAt' takes
-- another line (#455). Below the wing's widest point, y = 0.324, the line
-- crosses four faces folded onto two layers. Above it, the wing's sides are
-- creased to four small triangles folded inside it, and the line cuts those
-- too: a triangle it crossed without cutting would be joined both to paper
-- that turns and to paper that stays put. So the crease goes through every
-- layer of the wing, one segment per face. The segments form a bent chain on
-- the OPEN sheet but a straight hinge in the folded crane; their coordinates
-- come from undoing the fixture's fold transforms for the line. Creasing calls
-- the ordinary cutter and face tracer; ids are then selected from their
-- result, never carried across that boundary.
--
-- A line above the widest point also gets a join along the widest point in
-- each of the four faces, so the paper from the tip to the join is a triangle
-- in every layer, as the turning part is about 1/4, and the base between the
-- join and the hinge, four layers deep, has panels of its own.
--
-- Keep the original face zero first so adding the crease does not move the
-- crane's anchor. Choose the starting order with the tail tucked between the
-- body layers: the fixture's first valid order exposes it on one side. Flap
-- checks departure against the chosen order, including where the moving
-- hinge rests on the other wing. Valid contact alone does not identify the
-- traditional arrangement of a model with several possible stackings.
-- This recipe does not construct the crane from a square, move its other wing,
-- or expand its body. It exercises the production operation on a real fixture.
module CraneWing (CraneWing (..), buildCraneWing, buildCraneWingAt, studyHinge, craneStates, craneFile) where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find, partition, sort)
import Data.Text (Text)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Creasing (creaseAllAlong)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipSegment)
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Flat (Panel (..), Sheet (..), flatSheet)
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Stacking (defaultBudget, solveStackingAs)
import Senbazuru.Origami.Surface

data CraneWing = CraneWing
  { craneStart :: !Folded,
    craneHinge :: ![EdgeId],
    craneSide :: !FaceId,
    craneOpening :: !CheckedFlap,
    craneRefusal :: !Text,
    -- | The folded line y = h the wing turns about.
    craneHingeY :: !Double,
    -- | The folded y of the wing's widest point, where its sides are creased
    -- to the small triangles folded inside it.
    craneWidest :: !Double
  }
  deriving stock (Show)

-- | The line the studies have always used, a quarter of the sheet's side from
-- the wing's tip.
studyHinge :: Double
studyHinge = 0.25

buildCraneWing :: Frame -> Either Text CraneWing
buildCraneWing = buildCraneWingAt studyHinge

-- | Crease the wing along the folded line y = @hingeY@, which must cross it
-- between its tip and the body's underside.
buildCraneWingAt :: Double -> Frame -> Either Text CraneWing
buildCraneWingAt hingeY source = do
  unless (hingeY > 0 && hingeY < 0.5) $
    Left ("the wing crease must cross the wing between its tip at y = 0 and the body's underside at y = 1/2, not at y = " <> tshow hingeY)
  original <- first explain (foldFrameWith source)
  let material = foldedPattern original
  anchor <- case facesVertices material of
    ring : _ | length (facesVertices material) == 72 && sort ring == map VertexId [46, 49, 54, 55] -> Right ring
    _ -> Left "expected the material topology of examples/crane.fold"
  (segments, crossed, widest) <- wingSegments hingeY original
  creased <- first explain (creaseAllAlong segments material)
  let (anchors, rest) = partition ((== sort anchor) . sort) (facesVertices creased)
  unless (length anchors == 1) (Left "adding the wing crease changed the fixed anchor")
  folded <- first explain (foldFrameWith creased {facesVertices = anchors ++ rest})
  let frame = foldedFrame folded
      hinge = [EdgeId i | (i, assignment) <- zip [0 ..] (edgesAssignment frame), assignment == Unassigned]
  -- Each segment cuts one face in two, and only the line's segments are
  -- unassigned: the joins are J.
  unless (length hinge == crossed && length (facesVertices frame) == 72 + length segments) $
    Left ("expected " <> tshow crossed <> " wing-crease segments and " <> tshow (72 + length segments) <> " faces, not " <> tshow (length hinge) <> " and " <> tshow (length (facesVertices frame)))
  (u, v) <- case hinge of
    EdgeId i : _ -> case drop i (edgesVertices frame) of
      edge : _ -> Right edge
      [] -> Left "missing wing crease"
    [] -> Left "missing wing hinge"
  -- The face beside the hinge's first segment on the tip's side. It is found
  -- by where it lies, not by the tip's corner: above the widest point the face
  -- beside the hinge is the base, which the tip is not in.
  points <- first explain (frameVertices frame)
  let foldedY (VertexId i) = case drop i points of
        V3 _ y _ : _ -> y
        [] -> hingeY
  side <- case [FaceId i | (i, ring) <- zip [0 ..] (facesVertices frame), all (`elem` ring) [u, v], minimum (map foldedY ring) < hingeY - 1e-9] of
    [fid] -> Right fid
    _ -> Left "expected the wing tip on exactly one side of the hinge"
  -- Of this fixture's five orders, index 2 puts all eight tail faces between
  -- the two sides of the body. The regression checks these relations using
  -- material rings, so a change in enumeration cannot silently untuck it.
  orders <- first explain (solveStackingAs defaultBudget [2] frame)
  let start = folded {foldedFrame = frame {faceOrders = orders}}
  motion <- first explain (prepareFlapAlong hinge side 90 start >>= checkFlap defaultSweepSettings)
  refusal <- case prepareFlapAlong hinge side (-90) start >>= checkFlap defaultSweepSettings of
    Left err@(FlapEndpointOrder 0 _) -> Right (explain err)
    Left err -> Left ("unexpected wrong-direction refusal: " <> explain err)
    Right _ -> Left "the wing passed through its declared resting layer"
  pure (CraneWing start hinge side motion refusal hingeY widest)

-- The wing containing material corner (0,1) is faces 2, 3, 6 and 7 from its
-- tip to the body's underside, and 32, 34, 35 and 38, the triangles folded
-- inside it above its widest point. Its four faces have corners only at the
-- tip, at the widest point and on the underside, so the widest point is
-- their lowest corner past the tip. Clip the long line to each face it
-- crosses before taking it back to material space, and return the segments
-- with the number on the line and the widest point. This is a fixture recipe,
-- not selection of visible layers from a mouse click.
wingSegments :: Double -> Folded -> Either Text ([(V2, V2, Assignment)], Int, Double)
wingSegments hingeY folded = do
  sheet <- first explain (flatSheet (foldedFrame folded))
  faces <- traverse (panel sheet . FaceId) [2, 3, 6, 7]
  insides <- traverse (panel sheet . FaceId) [32, 34, 35, 38]
  let crosses p = let ys = [y | V2 _ y <- panelRing p] in minimum ys < hingeY - 1e-9 && maximum ys > hingeY + 1e-9
      widest = minimum (0.5 : [y | p <- faces, V2 _ y <- panelRing p, y > 1e-9])
  hinges <- traverse (share sheet hingeY Unassigned) (filter crosses (faces ++ insides))
  joins <- if hingeY > widest + 1e-9 then traverse (share sheet widest Join) faces else pure []
  pure (hinges ++ joins, length hinges, widest)
  where
    panel sheet fid = maybe (Left "missing crane wing face") Right (find ((== fid) . panelId) (sheetPanels sheet))
    share sheet lineY assignment face = do
      placement <- maybe (Left "missing crane wing placement") Right (IM.lookup (unFaceId (panelId face)) (foldedPlacements folded))
      (u, v) <- maybe (Left "wing crease missed a selected face") Right (clipSegment (panelRing face) (V2 0 lineY, V2 2 lineY))
      let back (V2 x y) = case applyRigid (inverse placement) (V3 x y (sheetPlane sheet)) of
            V3 a b _ -> V2 a b
      pure (back u, back v, assignment)

craneStates :: CraneWing -> Either Text [(Text, Surface V2)]
craneStates wing = traverse pose [0, 30, 60, 90 :: Int]
  where
    pose degrees = do
      sheet <- first explain (flapAt (craneOpening wing) (fromIntegral degrees / 90))
      pure (if degrees == 0 then "Start with the folded crane" else "Lower one wing · " <> tshow degrees <> "°", sheet)

craneFile :: [(Text, Surface V2)] -> FoldFile
craneFile states =
  FoldFile
    (Just 1.2)
    (Just "senbazuru checked crane wing")
    Nothing
    (Just "Lower one crane wing")
    Nothing
    ["diagrams"]
    emptyFrame
    [(materialFrame sheet) {frameTitle = Just title} | (title, sheet) <- states]
