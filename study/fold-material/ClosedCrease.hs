-- | One sharp crease between two bending rectangular panels. Each panel is
-- a side profile extended along y, so it is a surface made from straight
-- parallel lines. Rotating fixed-length profile segments preserves every
-- material triangle; those subdivision lines remain panel bends, not creases.
-- Only the middle crease shares vertices between the two material halves.
-- See docs/glossary.md for material coordinates, creases and layer orders.
--
-- Rational rotations make the prescribed profiles independently inspectable:
-- (1-t*t, 2*t)/(1+t*t) has exactly unit length. The difference of the two
-- profile heights is linear between their combined x breakpoints. Its extrema
-- therefore decide the ideal order without reusing triangle contact code.
-- These are prescribed static geometries, not equilibria or folding paths.
module ClosedCrease
  ( CreaseShape (..),
    ClosedCrease (..),
    ClosedCreaseError (..),
    Profile,
    closedCrease,
    closedCreaseWithWidth,
    profileGaps,
    profileCrossings,
    closedSurface,
  )
where

import Control.Monad (unless)
import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Bifunctor (first)
import Data.List (nub, sort)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import FoldBending
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact

type Profile = [(Rational, Rational)]

data CreaseShape = FlatTouching | BentTouching | Open | OpenSliver | Crossed | CrossedSliver | WrongSide
  deriving stock (Eq, Show, Enum, Bounded)

data ClosedCrease = ClosedCrease
  { closedMesh :: !MaterialMesh,
    closedOwners :: ![FaceId],
    closedHinges :: ![Hinge],
    closedRoot :: ![Int],
    lowerProfile :: !Profile,
    upperProfile :: !Profile
  }
  deriving stock (Show)

newtype ClosedCreaseError = ClosedCreaseError Text deriving stock (Eq, Show)

instance Explain ClosedCreaseError where explain (ClosedCreaseError message) = message

closedCrease :: Int -> CreaseShape -> Either ClosedCreaseError ClosedCrease
closedCrease subdivision = closedCreaseWithWidth subdivision 1

-- | Refine the extruded width independently. The original entry point keeps
-- three rows exactly; added rows share the same continuous crease and retain
-- distinct material vertices on the two contacting halves.
closedCreaseWithWidth :: Int -> Int -> CreaseShape -> Either ClosedCreaseError ClosedCrease
closedCreaseWithWidth subdivision width shape = do
  unless (width >= 1 && width <= 8) (Left (ClosedCreaseError "closed-crease width subdivision must be between 1 and 8"))
  unless (subdivision >= 1 && subdivision <= 8) (Left (ClosedCreaseError "closed-crease subdivision must be between 1 and 8"))
  let directions = if shape == FlatTouching then replicate 4 (1, 0) else map rotation [0, 1 / 10, 1 / 5, 3 / 10]
      opening i = case shape of
        Open -> 1 / 20
        OpenSliver -> 1 / 100000000
        Crossed -> if i == 0 then 1 / 100 else -(1 / 100)
        CrossedSliver -> if i == 0 then 1 / 100000000 else -(1 / 100000000)
        WrongSide -> -(1 / 100)
        _ -> 0
      turn (x, z) (c, s) = (c * x - s * z, s * x + c * z)
      upperDirections = [turn v (rotation (opening i)) | (i, v) <- zip [0 :: Int ..] directions]
      profile vectors = scanl (\(x, z) (dx, dz) -> (x + dx, z + dz)) (0, 0) [(dx / fromIntegral (8 * subdivision), dz / fromIntegral (8 * subdivision)) | (dx, dz) <- vectors, _ <- [1 .. subdivision]]
      lower = profile directions
      upper = profile upperDirections
      count = 4 * subdivision
      rows = 2 * width + 1
      -- Material x is negative on the upper, folded-over half. Refinement
      -- splits the original crease stiffness in proportion to segment length.
      half side ps = [materialSample (side * fromIntegral i / fromIntegral (2 * count)) y (V3 (fromRational x) y (fromRational z)) | (i, (x, z)) <- zip [0 :: Int ..] ps, j <- [0 .. rows - 1], let y = fromIntegral j / fromIntegral (rows - 1) - 0.5]
      lowerSamples = half 1 lower
      upperId i = if i < rows then i else length lowerSamples + i - rows
      cell i j = let a = rows * i + j; b = rows * (i + 1) + j in [(a, b, b + 1), (a, b + 1, a + 1)]
      lowerTriangles = concat [cell i j | i <- [0 .. count - 1], j <- [0 .. rows - 2]]
      mesh = Mesh (lowerSamples ++ drop rows (half (-1) upper)) (lowerTriangles ++ [(upperId a, upperId c, upperId b) | (a, b, c) <- lowerTriangles])
      rootHinge h = let (a, b, _, _) = hingeVertices h in if a < rows && b < rows then h {hingeRole = SurfaceCrease (EdgeId 0), hingeRest = pi, hingeStiffness = 0.5 / fromIntegral width} else h
  hinges <- first (ClosedCreaseError . explain) (buildPanelHinges (Bending 1 0.2) mesh)
  pure (ClosedCrease mesh (replicate (length lowerTriangles) (FaceId 0) ++ replicate (length lowerTriangles) (FaceId 1)) (map rootHinge hinges) [0 .. rows - 1] lower upper)

rotation :: Rational -> (Rational, Rational)
rotation t = ((1 - t * t) / (1 + t * t), 2 * t / (1 + t * t))

-- | Exact upper-minus-lower heights at every breakpoint in the common x
-- range. Profiles are monotone in x by construction. No triangle predicates,
-- distance snapping or floating-point trigonometry enter this reference.
profileGaps :: ClosedCrease -> [(Rational, Rational)]
profileGaps fixture = [(x, b - a) | x <- sort (nub (map fst lower ++ map fst upper)), Just a <- [height lower x], Just b <- [height upper x]]
  where
    lower = lowerProfile fixture
    upper = upperProfile fixture
    height ps x = case [z + (x - a) * (w - z) / (b - a) | ((a, z), (b, w)) <- zip ps (drop 1 ps), a <= x && x <= b] of
      value : _ -> Just value
      [] -> Nothing

-- | Interior crossings of the extruded profiles. An isolated zero bracketed
-- by opposite signs counts once; a shared segment of touching paper does not.
profileCrossings :: ClosedCrease -> [Rational]
profileCrossings fixture = nub (between ++ atVertex)
  where
    gaps = profileGaps fixture
    between = [x - a * (y - x) / (b - a) | ((x, a), (y, b)) <- zip gaps (drop 1 gaps), a * b < 0]
    atVertex = [x | ((_, a), (x, b), (_, c)) <- zip3 gaps (drop 1 gaps) (drop 2 gaps), b == 0, a * c < 0]

-- Export the same triangles and one source crease. Orders refer to the
-- upper triangles' reversed normals; their metadata retains two source panels.
-- Every prescribed profile progresses in +x, so those upper normals point
-- down. Above is therefore the FOLD sign for lower triangle a below upper b.
closedSurface :: ClosedCrease -> Either ClosedCreaseError (Surface V2)
closedSurface fixture = do
  candidates <- first (ClosedCreaseError . explain) (Contact.overlapCandidates (V3 0 0 1) (closedOwners fixture) mesh)
  let orders = [FaceOrder (FaceId a) (FaceId b) Above | candidate <- candidates, let (a, b) = Contact.candidateTriangles candidate]
  first (ClosedCreaseError . explain) (surfaceFromFrame (frame {faceOrders = orders}) >>= requireMaterialCoordinates)
  where
    mesh = closedMesh fixture
    key a b = (min a b, max a b)
    incidence = M.fromListWith (+) [(key a b, 1 :: Int) | (i, j, k) <- triangles mesh, (a, b) <- [(i, j), (j, k), (k, i)]]
    edges = M.toAscList incidence
    onCrease (a, b) = a `elem` closedRoot fixture && b `elem` closedRoot fixture
    assignment (edge, n) | onCrease edge = Valley | n == 1 = Border | otherwise = Join
    coords (V3 x y z) = [x, y, z]
    frame =
      emptyFrame
        { frameClasses = ["foldedForm"],
          frameAttributes = ["3D"],
          verticesCoords = map (coords . position) (samples mesh),
          facesVertices = [map VertexId [a, b, c] | (a, b, c) <- triangles mesh],
          edgesVertices = [(VertexId a, VertexId b) | ((a, b), _) <- edges],
          edgesAssignment = map assignment edges,
          frameExtras = KM.fromList [("senbazuru:material_coords", toJSON [[materialU p, materialV p] | p <- samples mesh]), ("senbazuru:source_panels", toJSON (map unFaceId (closedOwners fixture))), ("senbazuru:source_edges", toJSON [if onCrease edge then Just (0 :: Int) else Nothing | (edge, _) <- edges])]
        }
