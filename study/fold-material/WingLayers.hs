-- | Two touching wings made from ONE diamond folded at its middle crease.
-- Only vertices on that crease are shared. Coincident points elsewhere belong
-- to opposite halves of the original sheet and remain independent unknowns.
-- The upper half has negative material x and reversed spatial winding after
-- folding; its colour and FOLD order signs must respect that reversal.
-- See docs/glossary.md for material coordinates, panels and layer order.
--
-- Both roots and tip grips follow the one-layer experiment. Panel bending is
-- passive, while the original root crease prefers pi radians (fully closed).
-- This is a static, zero-thickness experiment: exact touching is permitted,
-- but geometry alone cannot select which coincident layer lies above the other.
module WingLayers
  ( WingLayers (..),
    LayerError (..),
    wingLayers,
    solveLayers,
    perturbUpper,
    offsetUpperGrip,
    layersSurface,
  )
where

import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Map.Strict qualified as M
import Data.Text (Text)
import FoldBending
import FoldRelaxation
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import WingBending (BendingPiece (..), wingPiece)

data WingLayers = WingLayers
  { layersMesh :: !MaterialMesh,
    layersPins :: !(IM.IntMap V3),
    layersHinges :: ![Hinge],
    layersOwners :: ![FaceId],
    layersPairs :: ![(Int, Int)],
    layersRoot :: ![Int],
    layersUpperGrip :: ![Int]
  }
  deriving stock (Show)

newtype LayerError = LayerError Text deriving stock (Eq, Show)

instance Explain LayerError where explain (LayerError message) = message

wingLayers :: Int -> Double -> Either LayerError WingLayers
wingLayers count degrees = do
  piece <- first (LayerError . explain) (wingPiece count degrees)
  let base = pieceMesh piece
      size = length (samples base)
      shared = count + 1
      upper i = if i < shared then i else size + i - shared
      reflected p = p {sampleMaterial = V2 (negate (materialU p)) (materialV p)}
      mesh =
        Mesh
          (samples base ++ map reflected (drop shared (samples base)))
          (triangles base ++ [(upper a, upper c, upper b) | (a, b, c) <- triangles base])
      pins = IM.union (piecePins piece) (IM.fromList [(upper i, p) | (i, p) <- IM.toList (piecePins piece)])
      vertices = IM.fromList (zip [0 ..] (samples mesh))
      crease h = let (a, b, _, _) = hingeVertices h in a < shared && b < shared
      rootHinge h =
        if crease h
          then
            let (a, b, _, _) = hingeVertices h
                len = maybe 0 (\(p, q) -> norm (sampleMaterial p ^-^ sampleMaterial q)) ((,) <$> IM.lookup a vertices <*> IM.lookup b vertices)
             in h {hingeRole = SurfaceCrease (EdgeId 0), hingeRest = pi, hingeStiffness = len}
          else h
      owners = replicate (length (triangles base)) (FaceId 0) ++ replicate (length (triangles base)) (FaceId 1)
  passive <- first (LayerError . explain) (buildPanelHinges (Bending 1 0.2) mesh)
  pure (WingLayers mesh pins (map rootHinge passive) owners [(i, upper i) | i <- [0 .. size - 1]] [0 .. shared - 1] (map upper (pieceGrip piece)))

solveLayers :: Settings -> WingLayers -> Either LayerError Relaxation
solveLayers settings fixture = do
  contact <- first (LayerError . explain) (Contact.prepareContact 0 (V3 0 0 1) [(FaceId 0, FaceId 1)] (layersOwners fixture) (layersMesh fixture))
  first (LayerError . explain) (relaxPinnedContact settings (layersPins fixture) (layersHinges fixture) contact (layersMesh fixture))

-- Move only free upper-layer points to exercise contact on an imperfect guess.
-- This is a solver input, never a folding-motion frame.
perturbUpper :: Double -> WingLayers -> WingLayers
perturbUpper amount fixture = fixture {layersMesh = mesh {samples = zipWith move [0 ..] (samples mesh)}}
  where
    mesh = layersMesh fixture
    move i p
      | materialU p < 0 && not (IM.member i (layersPins fixture)) =
          let t = (abs (materialU p) - 0.125) / 0.75
              wave = sin (pi * t)
           in p {position = position p ^+^ V3 0 0 (amount * wave * wave)}
    move _ p = p

-- Positive offsets lift the upper grip away from the lower one. A negative
-- offset deliberately asks it to sit underneath the declared lower layer;
-- an exact grip cannot be rescued by silently moving its targets.
offsetUpperGrip :: Double -> WingLayers -> WingLayers
offsetUpperGrip distance fixture = fixture {layersPins = foldr (IM.adjust (^+^ V3 0 0 distance)) (layersPins fixture) (layersUpperGrip fixture)}

-- Keep every triangle and material id. Numerical joins stay J; only the root
-- segments carry the single original crease id. The source-panel order is
-- expanded for the triangle faces, with signs relative to the UPPER normal.
layersSurface :: WingLayers -> MaterialMesh -> Either LayerError (Surface V2)
layersSurface fixture mesh = do
  if triangles mesh /= triangles (layersMesh fixture) || map sampleMaterial (samples mesh) /= map sampleMaterial (samples (layersMesh fixture))
    then Left (LayerError "layer export must preserve its original material and triangle ids")
    else Right ()
  overlaps <- first (LayerError . explain) (Contact.overlapCandidates (V3 0 0 1) (layersOwners fixture) mesh)
  let orders = [FaceOrder (FaceId a) (FaceId b) Above | candidate <- overlaps, let (a, b) = Contact.candidateTriangles candidate]
  first (LayerError . explain) (surfaceFromFrame frame {faceOrders = orders} >>= requireMaterialCoordinates)
  where
    incidence = M.fromListWith (+) [(key a b, 1 :: Int) | (i, j, k) <- triangles mesh, (a, b) <- [(i, j), (j, k), (k, i)]]
    key a b = (min a b, max a b)
    edges = M.toAscList incidence
    crease (a, b) = a `elem` layersRoot fixture && b `elem` layersRoot fixture
    assignment (edge, n)
      | crease edge = Valley
      | n == 1 = Border
      | otherwise = Join
    positions (V3 x y z) = [x, y, z]
    frame =
      emptyFrame
        { frameClasses = ["foldedForm"],
          frameAttributes = ["3D"],
          verticesCoords = map (positions . position) (samples mesh),
          edgesVertices = [(VertexId a, VertexId b) | ((a, b), _) <- edges],
          edgesAssignment = map assignment edges,
          facesVertices = [map VertexId [a, b, c] | (a, b, c) <- triangles mesh],
          frameExtras =
            KM.fromList
              [ ("senbazuru:material_coords", toJSON [[materialU p, materialV p] | p <- samples mesh]),
                ("senbazuru:source_panels", toJSON (map unFaceId (layersOwners fixture))),
                ("senbazuru:source_edges", toJSON [if crease edge then Just (0 :: Int) else Nothing | (edge, _) <- edges])
              ]
        }
