-- | Move the body specimen's grips while keeping its recovered deformation.
-- Subtracting the old analytic guess isolates the correction already earned
-- by the solver. Adding that displacement to the new guess retains it; using
-- the new analytic shape alone would discard the recovered seed. This is a
-- static initial guess, not an inextensible path or an accepted folded pose.
-- Material coordinates and shared triangle indices never change.
module BodyLargerOpening (openingGuess) where

import BodyPatch
import Control.Monad (unless)
import CraneSpread
import Data.IntMap.Strict qualified as IM
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface

openingGuess :: BodyPatch -> BodyPatch -> MaterialMesh -> Either SpreadError MaterialMesh
openingGuess old new recovered = do
  unless
    (patchDegrees old == 5 && patchDegrees new == 10 && patchLevel old == 1 && patchLevel new == 1)
    (bad "larger opening requires the declared refined 5-to-10-degree comparison")
  unless
    (spreadRefined a == spreadRefined b && spreadHinges a == spreadHinges b && spreadOrders a == spreadOrders b && IM.keys (spreadPins a) == IM.keys (spreadPins b) && patchMarks old == patchMarks new && patchFaces old == patchFaces new && patchCore old == patchCore new && patchEdges old == patchEdges new && patchVertices old == patchVertices new)
    (bad "larger opening changed material, bending preferences, source identities or held vertices")
  _ <- spreadSurface a recovered
  unless (spreadHeldError a recovered == 0) (bad "recovered seed moved an original hold")
  let moved = zipWith3 (\p q r -> p {position = position p ^+^ (position r ^-^ position q)}) (samples recovered) (samples (spreadMesh a)) (samples (spreadMesh b))
      held = [p {position = IM.findWithDefault (position p) i (spreadPins b)} | (i, p) <- zip [0 ..] moved]
  pure recovered {samples = held}
  where
    a = patchSpread old
    b = patchSpread new
    bad = Left . SpreadError
