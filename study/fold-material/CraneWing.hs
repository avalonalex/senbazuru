-- | Lower one wing of the traditional crane in examples/crane.fold.
-- The fixture finishes with both wings lying flat against the body. Add a
-- crease across one wing a quarter sheet-side from the (0,1) tip, then turn
-- its four material faces together through 90 degrees. A material face is a
-- region between creases; coincident faces remain different pieces of paper.
-- See docs/glossary.md for material coordinates, fold angles and layer order.
--
-- The new crease crosses four faces folded onto two layers. Its four segments
-- form a bent chain on the OPEN sheet, but a straight hinge in the folded
-- crane. Its coordinates come from undoing the fixture's fold transforms
-- for the line y=1/4. Creasing calls the ordinary cutter and face tracer; ids
-- are then selected from their result, never carried across that boundary.
--
-- Keep the original face zero first so adding the crease does not move the
-- crane's anchor. Solve the starting order once. Flap checks departure against
-- that order, including where the moving hinge rests on the other wing.
-- This recipe does not construct the crane from a square, move its other wing,
-- or expand its body. It exercises the production operation on a real fixture.
module CraneWing (CraneWing (..), buildCraneWing, craneStates, craneFile) where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.List (find, partition, sort)
import Data.Text (Text)
import Senbazuru.Explain (explain, tshow)
import Senbazuru.Fold.Creasing (creaseAllAlong)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipSegment)
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Flat (Panel (..), Sheet (..), flatSheet)
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Stacking (solveStacking)
import Senbazuru.Origami.Surface

data CraneWing = CraneWing
  { craneStart :: !Folded,
    craneHinge :: ![EdgeId],
    craneSide :: !FaceId,
    craneOpening :: !CheckedFlap,
    craneRefusal :: !Text
  }
  deriving stock (Show)

buildCraneWing :: Frame -> Either Text CraneWing
buildCraneWing source = do
  original <- first explain (foldFrameWith source)
  let material = foldedPattern original
  anchor <- case facesVertices material of
    ring : _ | length (facesVertices material) == 72 && sort ring == map VertexId [46, 49, 54, 55] -> Right ring
    _ -> Left "expected the material topology of examples/crane.fold"
  segments <- wingSegments original
  creased <- first explain (creaseAllAlong segments material)
  let (anchors, rest) = partition ((== sort anchor) . sort) (facesVertices creased)
  unless (length anchors == 1) (Left "adding the wing crease changed the fixed anchor")
  folded <- first explain (foldFrameWith creased {facesVertices = anchors ++ rest})
  let frame = foldedFrame folded
      hinge = [EdgeId i | (i, assignment) <- zip [0 ..] (edgesAssignment frame), assignment == Unassigned]
  unless (length hinge == 4 && length (facesVertices frame) == 76) (Left "expected four new wing-crease segments")
  (u, v) <- case hinge of
    EdgeId i : _ -> case drop i (edgesVertices frame) of
      edge : _ -> Right edge
      [] -> Left "missing wing crease"
    [] -> Left "missing wing hinge"
  side <- case [FaceId i | (i, ring) <- zip [0 ..] (facesVertices frame), all (`elem` ring) [u, v, VertexId 2]] of
    [fid] -> Right fid
    _ -> Left "expected the wing tip on exactly one side of the hinge"
  orders <- first explain (solveStacking frame)
  let start = folded {foldedFrame = frame {faceOrders = orders}}
  motion <- first explain (prepareFlapAlong hinge side 90 start >>= checkFlap defaultSweepSettings)
  refusal <- case prepareFlapAlong hinge side (-90) start >>= checkFlap defaultSweepSettings of
    Left err@(FlapEndpointOrder 0 _) -> Right (explain err)
    Left err -> Left ("unexpected wrong-direction refusal: " <> explain err)
    Right _ -> Left "the wing passed through its declared resting layer"
  pure (CraneWing start hinge side motion refusal)

-- Each named face belongs to the wing containing material corner (0,1).
-- Clip the long line to each face before taking it back to material space.
-- This is a fixture recipe, not selection of visible layers from a mouse click.
wingSegments :: Folded -> Either Text [(V2, V2, Assignment)]
wingSegments folded = do
  sheet <- first explain (flatSheet (foldedFrame folded))
  traverse (share sheet . FaceId) [2, 3, 6, 7]
  where
    share sheet fid = do
      panel <- maybe (Left "missing crane wing face") Right (find ((== fid) . panelId) (sheetPanels sheet))
      placement <- maybe (Left "missing crane wing placement") Right (IM.lookup (unFaceId fid) (foldedPlacements folded))
      (u, v) <- maybe (Left "wing crease missed a selected face") Right (clipSegment (panelRing panel) (V2 0 0.25, V2 2 0.25))
      let back (V2 x y) = case applyRigid (inverse placement) (V3 x y (sheetPlane sheet)) of
            V3 a b _ -> V2 a b
      pure (back u, back v, Unassigned)

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
