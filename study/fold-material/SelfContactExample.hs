-- | One uncreased strip curling back onto itself. Its triangles all belong to
-- the same source panel: local contact requirements must not split that panel
-- into fictitious creases. Original (u,v) coordinates describe a 1 by 0.3 sheet.
-- Placing each span at its original length and a turned direction gives a
-- bent strip without stretching its triangles; this is a pose, not motion.
--
-- Passive panel springs prefer zero bend. Additional BendControl springs act
-- at mesh edges across the width to impose a curl; these are illustrative external
-- controls, not paper's natural rest angles. With eight spans, each control
-- prefers 60 degrees and is four times its passive spring's stiffness, so the
-- free equilibrium prefers 48 degrees: (0 + 4*60)/5. That curl crosses itself.
-- Local requirements hold the returning end above the starting end instead.
module SelfContactExample (CurledPanel (..), CurlError (..), curledPanel) where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.IntMap.Strict qualified as IM
import Data.Text (Text)
import FoldBending
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))
import SurfaceContact qualified as Contact

data CurledPanel = CurledPanel
  { curlMesh :: !MaterialMesh,
    curlOwners :: ![FaceId],
    curlHinges :: ![Hinge],
    curlPairs :: ![(Int, Int)],
    curlContact :: !Contact.OrderedContact,
    curlBoundary :: ![(Int, Int)],
    curlClearance :: !Double
  }
  deriving stock (Eq, Show)

newtype CurlError = CurlError Text
  deriving stock (Eq, Show)

instance Explain CurlError where
  explain (CurlError message) = message

-- | The span count controls this strip's mesh; multiples of eight retain the
-- same material regions at its two ends. Only those regions receive contact forces.
curledPanel :: Int -> Either CurlError CurledPanel
curledPanel count = do
  unless (count >= 8 && count <= 64 && count `mod` 8 == 0) (Left (CurlError "curled panel needs a multiple of eight spans, from 8 to 64"))
  let n = fromIntegral count
      tangent i = let angle = fromIntegral i * 320 / n * pi / 180 in V3 (cos angle / n) 0 (sin angle / n)
      centerline = scanl (^+^) (V3 0 0 0) [tangent i | i <- [0 .. count - 1]]
      row (i, p) = [Sample (V2 (fromIntegral i / n) y) (p ^+^ V3 0 y 0) | y <- [0, 0.3]]
      spanTriangles i = let a = 2 * i in [(a, a + 2, a + 3), (a, a + 3, a + 1)]
      mesh = Mesh (concatMap row (zip [0 :: Int ..] centerline)) (concatMap spanTriangles [0 .. count - 1])
      vertices = IM.fromList (zip [0 ..] (samples mesh))
      transverse hinge = let (a, b, _, _) = hingeVertices hinge in a `div` 2 == b `div` 2
      clearance = 1e-6
      lower = [0 .. count `div` 4 - 1]
      upper = [2 * count - count `div` 4 .. 2 * count - 1]
      pairs = [(a, b) | a <- lower, b <- upper]
      boundary = (0, 1) : (2 * count, 2 * count + 1) : [(2 * i + side, 2 * (i + 1) + side) | i <- [0 .. count - 1], side <- [0, 1]]
  passive <- first (CurlError . explain) (buildPanelHinges defaultBending mesh)
  controls <- mapM (drive vertices n) (filter transverse passive)
  contact <- first (CurlError . explain) (Contact.prepareTriangleContact clearance (V3 0 0 1) pairs mesh)
  pure (CurledPanel mesh (replicate (length (triangles mesh)) (FaceId 0)) (passive ++ controls) pairs contact boundary clearance)
  where
    drive vertices n hinge = do
      (angle, _) <- first (CurlError . explain) (hingeAngle hinge vertices)
      pure hinge {hingeRole = BendControl, hingeRest = signum angle * 480 / n * pi / 180, hingeStiffness = 4 * hingeStiffness hinge}
